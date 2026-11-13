#[cfg(target_os = "linux")]
mod linux;

#[cfg(any(target_os = "linux", test))]
use image::{imageops, RgbImage};
use std::{ffi::OsString, path::PathBuf};

const USAGE: &str = "Uso: fbi [-T VT] -reset | fbi [-T VT] [-a] [-noverbose] [--once] <imagem>";

#[derive(Debug, PartialEq)]
enum Action {
    Help,
    Clear,
    Show(PathBuf),
}

#[derive(Debug, PartialEq)]
struct Options {
    vt: Option<u16>,
    fit: bool,
    once: bool,
    action: Action,
}

fn parse(args: impl IntoIterator<Item = OsString>) -> Result<Options, String> {
    let mut args = args.into_iter();
    let mut vt = None;
    let mut fit = false;
    let mut once = false;
    let mut clear = false;
    let mut path = None;
    let mut positional = false;
    while let Some(arg) = args.next() {
        if !positional {
            match arg.to_str() {
                Some("-h" | "--help") => {
                    return Ok(Options {
                        vt,
                        fit,
                        once,
                        action: Action::Help,
                    })
                }
                Some("-T") => {
                    vt = Some(
                        args.next()
                            .and_then(|value| value.to_str()?.parse::<u16>().ok())
                            .filter(|&number| (1..=63).contains(&number))
                            .ok_or("-T requer um terminal virtual entre 1 e 63")?,
                    );
                    continue;
                }
                Some("-a") => {
                    fit = true;
                    continue;
                }
                Some("-reset" | "--reset") => {
                    clear = true;
                    continue;
                }
                Some("-noverbose" | "--noverbose") => continue,
                Some("--once") => {
                    once = true;
                    continue;
                }
                Some("--") => {
                    positional = true;
                    continue;
                }
                _ if arg.to_string_lossy().starts_with('-') => {
                    return Err(format!("opção desconhecida: {}", arg.to_string_lossy()));
                }
                _ => {}
            }
        }
        if path.replace(PathBuf::from(arg)).is_some() {
            return Err("informe apenas uma imagem".into());
        }
    }
    let action = match (clear, path) {
        (true, None) if !once => Action::Clear,
        (false, Some(path)) => Action::Show(path),
        _ => return Err("informe uma imagem ou -reset".into()),
    };
    Ok(Options {
        vt,
        fit,
        once,
        action,
    })
}

#[cfg(any(target_os = "linux", test))]
fn frame(source: &RgbImage, width: u32, height: u32, fit: bool) -> RgbImage {
    let resized;
    let source = if fit {
        let scale = (f64::from(width) / f64::from(source.width()))
            .min(f64::from(height) / f64::from(source.height()));
        resized = imageops::resize(
            source,
            ((f64::from(source.width()) * scale).round() as u32).clamp(1, width),
            ((f64::from(source.height()) * scale).round() as u32).clamp(1, height),
            imageops::FilterType::Triangle,
        );
        &resized
    } else {
        source
    };

    let mut output = RgbImage::new(width, height);
    let visible = imageops::crop_imm(
        source,
        source.width().saturating_sub(width) / 2,
        source.height().saturating_sub(height) / 2,
        source.width().min(width),
        source.height().min(height),
    );
    imageops::replace(
        &mut output,
        &visible.to_image(),
        i64::from(width.saturating_sub(source.width()) / 2),
        i64::from(height.saturating_sub(source.height()) / 2),
    );
    output
}

fn main() -> std::process::ExitCode {
    match parse(std::env::args_os().skip(1)) {
        Ok(options) if options.action == Action::Help => {
            println!("{USAGE}");
            std::process::ExitCode::SUCCESS
        }
        Ok(options) => match run(options) {
            Ok(()) => std::process::ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("fbi: {error}");
                std::process::ExitCode::FAILURE
            }
        },
        Err(error) => {
            eprintln!("fbi: {error}\n{USAGE}");
            std::process::ExitCode::from(2)
        }
    }
}

#[cfg(target_os = "linux")]
fn run(options: Options) -> Result<(), Box<dyn std::error::Error>> {
    linux::run(options)
}

#[cfg(not(target_os = "linux"))]
fn run(_: Options) -> Result<(), Box<dyn std::error::Error>> {
    Err("a exibição requer o framebuffer do Linux".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_signaged_commands() {
        let args = |args: &[&str]| parse(args.iter().map(OsString::from));
        assert_eq!(args(&["-T", "2", "-reset"]).unwrap().action, Action::Clear);
        let image = args(&["-T", "2", "-a", "-noverbose", "file with spaces.png"]).unwrap();
        assert_eq!(image.vt, Some(2));
        assert!(image.fit);
        assert_eq!(image.action, Action::Show("file with spaces.png".into()));
        assert!(args(&["-T", "0", "-reset"]).is_err());
        assert!(args(&["-reset", "image.png"]).is_err());
    }

    #[test]
    fn scales_proportionally_and_centers_on_black() {
        let source = RgbImage::from_pixel(2, 1, image::Rgb([255, 0, 0]));
        let result = frame(&source, 4, 4, true);
        assert_eq!(result.get_pixel(0, 0).0, [0, 0, 0]);
        assert_eq!(result.get_pixel(3, 1).0, [255, 0, 0]);
        assert_eq!(result.get_pixel(3, 2).0, [255, 0, 0]);
        assert_eq!(result.get_pixel(0, 3).0, [0, 0, 0]);
    }
}
