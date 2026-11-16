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
Ruby 4.0.9, as gems do projeto e o `mpv` em uma VM com a conta
`pi` e o projeto em `/home/pi/signaged`. O Vagrant seleciona a
arquitetura do host (ARM64 ou AMD64). Se precisar usar uma cópia da box
Bento fora do catálogo padrão, passe a URL da box VirtualBox da arquitetura
correta em `SIGNAGED_VM_BOX_URL`.

Por padrão, a VM serve uma programação local com a imagem de carregamento.
`signaged.service` e `signaged_player.service` iniciam automaticamente no
boot. O `mpv` exibe vídeos e imagens diretamente via DRM/KMS no VT 2.
Quando a programação está vazia, o player exibe um quadro preto.

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

## Implantação por Ansible

Instale `ansible-core` na máquina de controle. O destino precisa rodar
Raspberry Pi OS, Debian ou Ubuntu com systemd, ter Python 3 e aceitar SSH com
sudo. Copie `deploy/ansible/inventory.example.yml` para um inventário local
e preencha o endereço, usuário SSH, servidor e serial cadastrado.

Configure `signaged_git_repo` e `signaged_git_branch` com o repositório e
a branch que o dispositivo deverá acompanhar. O usuário `pi` no destino
precisa ter acesso de leitura ao repositório para o checkout e as atualizações.

Para uma VM já criada com Vagrant, use `signaged_platform: virtualbox` e
consulte `vagrant ssh-config` para obter host, porta, usuário e chave.
Para um Pi, use `signaged_platform: pi`. O player requer DRM/KMS para exibir conteúdo no console.

```sh
ansible-playbook -i /caminho/inventory.yml deploy/ansible/deploy.yml --limit pi_sala
```

O playbook instala Ruby 4.0.9 e mpv, clona a aplicação em
`/home/pi/signaged`, e grava
o `.env` com os valores do inventário. Ele habilita e inicia
`signaged.service`, `signaged_player.service` e `git_update.service`.
A primeira execução pode demorar durante a compilação do Ruby.

### VM Debian 13 ARM64 para simular o ambiente do Raspberry Pi

Em um host ARM64 com VirtualBox e Vagrant, execute na raiz:

```sh
./support/virtualbox/up.sh raspberry-pi
vagrant ssh raspberry-pi -c 'cat /etc/os-release; dpkg --print-architecture; apt-cache policy mpv kbd'
```

A VM `raspberry-pi` é separada da VM Ubuntu e usa o mesmo provisionamento
do Signaged. Ela usa Debian 13 ARM64 com os repositórios da box e o hardware
gráfico virtual do VirtualBox. Use o Pi físico para validar aceleração,
desempenho e saída HDMI. Para uma cópia externa da box Debian, configure
`SIGNAGED_PI_BOX_URL`.

A VM `raspberry-pi` usa VLC para vídeos e o `fbi-vetor` para imagens e tela preta no framebuffer EFI (`/dev/fb0`) via VT 2 e
herda o servidor e o serial do `.env`. Use `SIGNAGED_PI_SERVER` e
`SIGNAGED_PI_SERIAL` para sobrescrever esses valores só na VM Debian. Defina
`SIGNAGED_PI_SERVER=` para forçar a demonstração local.

O caminho de instalação padrão é definido em [`install-root`](install-root).
