# fbi-vetor

Visualizador de imagem local para o framebuffer Linux. O executável se chama
`fbi` para funcionar com o Signaged. Aceita PNG, JPEG, BMP e PNM. Com `-a`,
a imagem é centralizada em fundo preto e redimensionada mantendo a proporção.

```sh
fbi -T 2 -a -noverbose /caminho/imagem.png
fbi -T 2 -reset
```

Por padrão a imagem permanece em exibição até o processo receber SIGTERM
(`killall fbi`), SIGINT, SIGHUP ou SIGQUIT. Nesse caso o programa limpa a
imagem e restaura o modo do console. `--once` desenha a imagem e retorna,
restaurando o console imediatamente. A visibilidade após essa restauração
depende do driver e do terminal ativo. `-noverbose` é aceito por compatibilidade.
Erros vão para stderr.

O Raspberry Pi precisa expor um framebuffer fbdev truecolor de 16, 24 ou 32
bits e um terminal virtual Linux. O processo precisa de acesso aos dispositivos
`/dev/tty0`, `/dev/ttyN` e `/dev/fbN` e permissão para trocar de VT. Os
serviços do Signaged que exibem imagens rodam como root. A variável
`FRAMEBUFFER` permite indicar o dispositivo explicitamente.

## Compilar e instalar no Raspberry Pi

Com Rust 1.85 ou posterior, Cargo e Make instalados, execute nesta pasta:

```sh
make test
make
sudo install -m 0755 target/release/fbi /usr/local/bin/fbi
```

O alvo `make install` também compila e instala. Aceita `PREFIX`, `DESTDIR`,
`TARGET` e `TARGET_DIR` para instalação em outro prefixo ou empacotamento.

## Compilar em outra máquina

Para executar os testes em Linux via Docker, use `docker buildx build --target test .`.

Com Docker Buildx, gere um binário Linux estático para o sistema do Pi.
Use o alvo de acordo com a arquitetura do **sistema instalado**, não só com
o processador. Execute os comandos nesta pasta:

```sh
# Raspberry Pi OS de 64 bits (aarch64)
docker buildx build --build-arg TARGET=aarch64-unknown-linux-musl \
  --output type=local,dest=dist/arm64 .

# Raspberry Pi OS de 32 bits em CPU ARMv7 ou mais recente
docker buildx build --build-arg TARGET=armv7-unknown-linux-musleabihf \
  --output type=local,dest=dist/armv7 .
```

Em placas ARMv6, como Pi 1 e Pi Zero original, use a compilação nativa com um
toolchain compatível com ARMv6. Após copiar o binário apropriado para o Pi,
execute `sudo install -m 0755 fbi /usr/local/bin/fbi` e confirme com
`command -v fbi` que o serviço resolve o executável esperado.
