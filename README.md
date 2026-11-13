# Signaged

## Testes com Docker Compose

```sh
docker compose up
```

O serviço `test` executa o RSpec ao iniciar e usa a imagem oficial Ruby 2.6.3 baseada em Debian. O relatório
fica disponível em `coverage/index.html` no projeto. Para reconstruir a imagem
após editar o código e propagar o código de saída da suíte, use
`docker compose up --build --exit-code-from test`.

## Testes locais

Com Ruby 2.6.3, instale o Bundler 2.4.22 e rode a suíte na raiz do projeto.

```sh
gem install bundler -v 2.4.22
bundle _2.4.22_ install
bundle _2.4.22_ exec rspec
```

O SimpleCov gera o relatório em `coverage/index.html`. A suíte exige 100% de
cobertura de linhas em cada arquivo Ruby de `bin/` e `lib/`. Os testes simulam
a rede, os comandos do Raspberry Pi e a gravação da configuração de Wi-Fi.

## Ambiente no VirtualBox

Com VirtualBox 7.2 e Vagrant 2.4 ou posterior instalados no host, rode na
raiz do projeto:

```sh
./support/virtualbox/up.sh
```

O script cria e inicia uma VM Ubuntu 24.04 com janela gráfica e provisiona
Ruby 4.0.9, as gems do projeto e o `fbi-vetor` em uma VM com a conta
`tvopen` e o projeto em `/home/tvopen/signaged`. O Vagrant seleciona a
arquitetura do host (ARM64 ou AMD64). Se precisar usar uma cópia da box
Bento fora do catálogo padrão, passe a URL da box VirtualBox da arquitetura
correta em `SIGNAGED_VM_BOX_URL`.

Por padrão, a VM serve uma programação local com a imagem de carregamento.
`signaged.service` e `signaged_player.service` iniciam automaticamente no
boot. A VM exibe imagens no VT 2 via mpv/DRM. O comando `fbi` da VM
encaminha a limpeza do framebuffer ao binário Rust. A demo exercita imagens. Para vídeos, a VM instala o
mpv e um comando de compatibilidade `omxplayer` em `/usr/local/bin`. O
comando mantém as opções usadas pelo Signaged, incluindo a reprodução sem
áudio. A saída de vídeo requer DRM/KMS no convidado.

Para usar um servidor e um dispositivo já cadastrados, configure o `.env`
na raiz do projeto:

```dotenv
SERVER_NAME=https://seu-servidor.example
SIGNAGED_SERIAL=seuSerial
```

A VM também aceita `SIGNAGED_SERVER` como nome para a URL. Variáveis
definidas no shell têm precedência sobre o `.env`. Sem URL configurada,
o provisionamento usa a programação local.

O script também reaplica o provisionamento de uma VM existente. Para parar,
retomar ou consultar os logs, use:

```sh
vagrant halt
vagrant up
vagrant ssh -c 'sudo journalctl -u signaged -u signaged_player -n 50'
```
