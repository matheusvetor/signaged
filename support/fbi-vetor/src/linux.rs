use crate::{frame, Action, Options};
use image::RgbImage;
use std::{
    error::Error,
    fs::{File, OpenOptions},
    io,
    os::fd::AsRawFd,
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::Duration,
};

const FBIOGET_VSCREENINFO: u32 = 0x4600;
const FBIOGET_FSCREENINFO: u32 = 0x4602;
const FBIOGET_CON2FBMAP: u32 = 0x460f;
const VT_GETSTATE: u32 = 0x5603;
const VT_ACTIVATE: u32 = 0x5606;
const VT_WAITACTIVE: u32 = 0x5607;
const KDGETMODE: u32 = 0x4b3b;
const KDSETMODE: u32 = 0x4b3a;
const KD_GRAPHICS: libc::c_ulong = 1;
static STOP: AtomicBool = AtomicBool::new(false);

// ABI de linux/fb.h e linux/vt.h. Os campos unsigned long seguem a ABI ARM.
#[repr(C)]
#[derive(Default)]
struct FixedInfo {
    id: [u8; 16],
    smem_start: libc::c_ulong,
    smem_len: u32,
    kind: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: libc::c_ulong,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [u16; 2],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct Channel {
    offset: u32,
    length: u32,
    msb_right: u32,
}

#[repr(C)]
#[derive(Default)]
struct VariableInfo {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: Channel,
    green: Channel,
    blue: Channel,
    alpha: Channel,
    remaining: [u32; 20],
}

#[repr(C)]
#[derive(Default)]
struct VtState {
    active: u16,
    signal: u16,
    state: u16,
}

#[repr(C)]
struct ConsoleMap {
    console: u32,
    framebuffer: u32,
}

fn device(path: impl AsRef<Path>) -> io::Result<File> {
    let path = path.as_ref();
    OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .map_err(|error| io::Error::new(error.kind(), format!("{}: {error}", path.display())))
}

fn ioctl_ptr<T>(file: &File, request: u32, value: &mut T) -> io::Result<()> {
    // The request and the pointed-to Linux ABI type are paired at each call site.
    let result = unsafe { libc::ioctl(file.as_raw_fd(), request as _, value as *mut T) };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn ioctl_value(file: &File, request: u32, value: libc::c_ulong) -> io::Result<()> {
    let result = unsafe { libc::ioctl(file.as_raw_fd(), request as _, value) };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

struct Console {
    tty: File,
    previous: u16,
    target: u16,
    original_mode: libc::c_int,
    restore: bool,
}

impl Console {
    fn open(target: Option<u16>) -> io::Result<Self> {
        let control = device("/dev/tty0")?;
        let mut state = VtState::default();
        ioctl_ptr(&control, VT_GETSTATE, &mut state)?;
        let target = target.unwrap_or(state.active);
        let tty = device(format!("/dev/tty{target}"))?;
        let mut original_mode = 0;
        ioctl_ptr(&tty, KDGETMODE, &mut original_mode)?;
        Ok(Self {
            tty,
            previous: state.active,
            target,
            original_mode,
            restore: false,
        })
    }

    fn activate(&mut self) -> io::Result<()> {
        self.restore = true;
        ioctl_value(&self.tty, KDSETMODE, KD_GRAPHICS)?;
        if self.previous != self.target {
            ioctl_value(&self.tty, VT_ACTIVATE, self.target.into())?;
            ioctl_value(&self.tty, VT_WAITACTIVE, self.target.into())?;
        }
        Ok(())
    }

    fn restore(&mut self) -> io::Result<()> {
        self.restore = false;
        let switch = if self.previous != self.target {
            ioctl_value(&self.tty, VT_ACTIVATE, self.previous.into())
                .and_then(|()| ioctl_value(&self.tty, VT_WAITACTIVE, self.previous.into()))
        } else {
            Ok(())
        };
        let mode = ioctl_value(&self.tty, KDSETMODE, self.original_mode as _);
        switch.and(mode)
    }
}

impl Drop for Console {
    fn drop(&mut self) {
        if self.restore {
            let _ = self.restore();
        }
    }
}

// fbdev can expose a shadow buffer to write(2). Map the scanout memory as fbi does.
struct Mapping {
    address: *mut libc::c_void,
    length: usize,
    offset: usize,
}

impl Mapping {
    fn open(file: &File, info: &FixedInfo) -> io::Result<Self> {
        let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        if page_size <= 0 {
            return Err(io::Error::last_os_error());
        }
        let offset = (info.smem_start % page_size as libc::c_ulong) as usize;
        let length = (info.smem_len as usize)
            .checked_add(offset)
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "framebuffer mapping too large")
            })?;
        let address = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                length,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                file.as_raw_fd(),
                0,
            )
        };
        if address == libc::MAP_FAILED {
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            address,
            length,
            offset,
        })
    }

    fn write_row(&mut self, offset: usize, row: &[u8]) {
        // Framebuffer::open validates the full viewport against the mapped length.
        unsafe {
            std::ptr::copy_nonoverlapping(
                row.as_ptr(),
                self.address.cast::<u8>().add(self.offset + offset),
                row.len(),
            );
        }
    }
}

impl Drop for Mapping {
    fn drop(&mut self) {
        unsafe { libc::munmap(self.address, self.length) };
    }
}

struct Framebuffer {
    mapping: Mapping,
    info: VariableInfo,
    stride: u64,
    pixel_size: usize,
}

impl Framebuffer {
    fn open(vt: u16) -> Result<Self, Box<dyn Error>> {
        let file = if let Some(path) = std::env::var_os("FRAMEBUFFER") {
            device(path)?
        } else {
            let fb0 = device("/dev/fb0")?;
            let mut mapping = ConsoleMap {
                console: vt.into(),
                framebuffer: 0,
            };
            match ioctl_ptr(&fb0, FBIOGET_CON2FBMAP, &mut mapping) {
                Ok(()) if mapping.framebuffer != 0 => {
                    device(format!("/dev/fb{}", mapping.framebuffer))?
                }
                Ok(()) => fb0,
                // Some fbdev drivers do not implement console mappings.
                Err(error) if matches!(error.raw_os_error(), Some(libc::EINVAL | libc::ENOTTY)) => {
                    fb0
                }
                Err(error) => return Err(error.into()),
            }
        };
        let mut info = VariableInfo::default();
        let mut fixed = FixedInfo::default();
        ioctl_ptr(&file, FBIOGET_VSCREENINFO, &mut info)?;
        ioctl_ptr(&file, FBIOGET_FSCREENINFO, &mut fixed)?;
        if fixed.kind != 0
            || fixed.visual != 2
            || info.grayscale != 0
            || !matches!(info.bits_per_pixel, 16 | 24 | 32)
            || info.xres == 0
            || info.yres == 0
        {
            return Err("framebuffer requer pixels truecolor de 16, 24 ou 32 bits".into());
        }

        let pixel_size = (info.bits_per_pixel / 8) as usize;
        let stride = u64::from(fixed.line_length);
        let right = u64::from(info.xoffset) + u64::from(info.xres);
        let bottom = u64::from(info.yoffset) + u64::from(info.yres);
        let row_end = right * pixel_size as u64;
        let end = (bottom - 1)
            .checked_mul(stride)
            .and_then(|offset| offset.checked_add(row_end));
        if row_end > stride || !matches!(end, Some(value) if value <= u64::from(fixed.smem_len)) {
            return Err("dimensões do framebuffer excedem a memória disponível".into());
        }

        let mut used = 0;
        for channel in [info.red, info.green, info.blue, info.alpha] {
            if channel.length == 0 {
                continue;
            }
            if channel.length > 16
                || channel.offset >= info.bits_per_pixel
                || channel.length > info.bits_per_pixel - channel.offset
                || channel.msb_right != 0
            {
                return Err("layout de canais do framebuffer não suportado".into());
            }
            let mask = ((1u32 << channel.length) - 1) << channel.offset;
            if used & mask != 0 {
                return Err("canais do framebuffer se sobrepõem".into());
            }
            used |= mask;
        }
        if [info.red, info.green, info.blue]
            .iter()
            .any(|channel| channel.length == 0)
        {
            return Err("framebuffer sem canais RGB completos".into());
        }
        Ok(Self {
            mapping: Mapping::open(&file, &fixed)?,
            info,
            stride,
            pixel_size,
        })
    }

    fn write(&mut self, image: Option<&RgbImage>) {
        let mut row = vec![0; self.info.xres as usize * self.pixel_size];
        let xoffset = u64::from(self.info.xoffset) * self.pixel_size as u64;
        for y in 0..self.info.yres {
            for (x, bytes) in row.chunks_exact_mut(self.pixel_size).enumerate() {
                let [r, g, b] = image.map_or([0, 0, 0], |image| image.get_pixel(x as u32, y).0);
                let pixel = pack(r, self.info.red)
                    | pack(g, self.info.green)
                    | pack(b, self.info.blue)
                    | pack(255, self.info.alpha);
                let native = pixel.to_ne_bytes();
                let start = if cfg!(target_endian = "big") {
                    4 - self.pixel_size
                } else {
                    0
                };
                bytes.copy_from_slice(&native[start..start + self.pixel_size]);
            }
            let offset = (u64::from(self.info.yoffset) + u64::from(y)) * self.stride + xoffset;
            self.mapping.write_row(offset as usize, &row);
        }
    }
}

fn pack(value: u8, channel: Channel) -> u32 {
    if channel.length == 0 {
        return 0;
    }
    let maximum = (1u32 << channel.length) - 1;
    ((u32::from(value) * maximum + 127) / 255) << channel.offset
}

extern "C" fn stop(_: libc::c_int) {
    STOP.store(true, Ordering::Relaxed);
}

fn install_signal_handlers() -> io::Result<()> {
    // The handler only sets an atomic flag. Cleanup runs in normal control flow.
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = stop as *const () as libc::sighandler_t;
        action.sa_flags = libc::SA_RESTART;
        libc::sigemptyset(&mut action.sa_mask);
        for signal in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP, libc::SIGQUIT] {
            if libc::sigaction(signal, &action, std::ptr::null_mut()) < 0 {
                return Err(io::Error::last_os_error());
            }
        }
    }
    Ok(())
}

pub fn run(options: Options) -> Result<(), Box<dyn Error>> {
    install_signal_handlers()?;
    let source = match options.action {
        Action::Show(path) => {
            let reader = image::io::Reader::open(&path)?.with_guessed_format()?;
            Some(reader.decode()?.to_rgb8())
        }
        Action::Clear => None,
        Action::Help => unreachable!(),
    };
    let mut console = Console::open(options.vt)?;
    let mut framebuffer = Framebuffer::open(console.target)?;
    let rendered = source.as_ref().map(|image| {
        frame(
            image,
            framebuffer.info.xres,
            framebuffer.info.yres,
            options.fit,
        )
    });
    if STOP.load(Ordering::Relaxed) {
        return Ok(());
    }
    console.activate()?;
    framebuffer.write(rendered.as_ref());
    if rendered.is_some() && !options.once {
        while !STOP.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(50));
        }
        framebuffer.write(None);
    }
    console.restore()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_kernel_structure_sizes() {
        assert_eq!(std::mem::size_of::<VariableInfo>(), 160);
        assert_eq!(std::mem::size_of::<VtState>(), 6);
        assert_eq!(std::mem::size_of::<ConsoleMap>(), 8);
        let fixed_size = if cfg!(target_pointer_width = "64") {
            80
        } else {
            68
        };
        assert_eq!(std::mem::size_of::<FixedInfo>(), fixed_size);
    }

    #[test]
    fn packs_rgb565_channels() {
        let red = Channel {
            offset: 11,
            length: 5,
            msb_right: 0,
        };
        let green = Channel {
            offset: 5,
            length: 6,
            msb_right: 0,
        };
        assert_eq!(pack(255, red) | pack(255, green), 0xffe0);
        assert_eq!(pack(0, red), 0);
    }
}
