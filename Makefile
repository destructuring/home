SHELL := /bin/bash

.PHONY: docs

menu:
	@perl -ne 'printf("%10s: %s\n","$$1","$$2") if m{^([\w+-]+):[^#]+#\s(.+)$$}' Makefile

thing: # Upgrade all the things
	./env.sh $(MAKE) thing-inner

thing-inner:
	-$(MAKE) update
	$(MAKE) update
	$(MAKE) install

rebuild-python:
	rm -rf .pyenv venv .local/pipx
	$(MAKE) pyenv-python
	$(MAKE) python
	$(MAKE) pipx

update: # Update code
	git pull
	git submodule sync
	git submodule update --init --recursive --remote
	$(MAKE) update_password_store
	$(MAKE) update_inner

list-all: # Update asdf plugin versions
	runmany 4 'echo $$1; asdf list-all $$1 | sort > .tool-versions-$$1' consul packer vault golang kubectl kind kustomize helm k3sup nomad terraform

update_password_store:
	if cd .password-store && git reset --hard origin/master; then chmod 600 ssh/config; fi
	if cd .password-store && git pull; then chmod 600 ssh/config; fi

update_inner:
	if [[ ! -d .asdf/.git ]]; then git clone https://github.com/asdf-vm/asdf.git asdf; mv asdf/.git .asdf/; rm -rf asdf; cd .asdf && git reset --hard; fi
	git submodule update --init
	mkdir -p .ssh && chmod 700 .ssh
	mkdir -p .gnupg && chmod 700 .gnupg
	mkdir -p .aws
	mkdir -p .docker
	(cat .docker/config.json 2>/dev/null || echo '{}') | jq -S '. + {credsStore: "pass", "credHelpers": { "docker.io": "pass" }}' > .docker/config.json.1
	mv .docker/config.json.1 .docker/config.json
	rm -f .profile

upgrade: # Upgrade installed software
	brew upgrade
	if [[ "$(shell uname -s)" == "Darwin" ]]; then brew upgrade --cask; fi
	pipx upgrade-all

install-aws:
	sudo yum install -y jq htop
	sudo yum install -y expat-devel readline-devel openssl-devel bzip2-devel sqlite-devel
	/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
	cd .. && homedir/bin/install-homedir

setup-do:
	./env.sh $(MAKE) setup-do-inner

setup-do-inner:
	sudo mount -o defaults,nofail,discard,noatime /dev/disk/by-id/* /mnt
	for s in /swap0 /swap1 /swap2 /swap3; do \
		sudo fallocate -l 1G $$s; \
		sudo chmod 0600 $$s; \
		sudo mkswap $$s; \
		echo $$s swap swap defaults 0 0 | sudo tee -a /etc/fstab; \
	done
	while ! (test -e /dev/sda || test -e /dev/sdb); do date; sleep 5; done
	-sudo e2label /dev/sda mnt
	-sudo e2label /dev/sdb mnt
	echo LABEL=mnt /mnt ext4 defaults 0 0 | sudo tee -a /etc/fstab
	-sudo umount /mnt
	sudo mount /mnt
	sudo install -d -o 1000 -g 1000 /mnt/password-store /mnt/work
	ln -nfs /mnt/password-store .password-store
	ln -nfs /mnt/work work
	make update install

setup-aws:
	sudo perl -pe 's{^#\s*GatewayPorts .*}{GatewayPorts yes}' /etc/ssh/sshd_config | grep Gateway

setup-dummy:
	bin/setup-dummy

setup-registry:
	docker run -d -p 5000:5000 --restart=always --name registry registry:2

install: # Install software bundles
	source ./.bash_profile && ( $(MAKE) install_inner || true )
	@bin/fig cleanup
	rm -f /home/linuxbrew/.linuxbrew/bin/perl

install_inner:
	$(MAKE) brew
	$(MAKE) asdf
	$(MAKE) python
	$(MAKE) pipx
	$(MAKE) misc

pyenv .pyenv/bin/pyenv:
	@bin/fig pyenv
	brew install pyenv
	#curl -sSL https://pyenv.run | bash

python: .pyenv/bin/pyenv
	if test -w /usr/local/bin; then ln -nfs python3 /usr/local/bin/python; fi
	if test -w /home/linuxbrew/.linuxbrew/bin; then ln -nfs python3 /home/linuxbrew/.linuxbrew/bin/python; fi
	if ! venv/bin/python --version 2>/dev/null; then \
		rm -rf venv; bin/fig python; source ./.bash_profile && python3 -m venv venv && venv/bin/python bin/get-pip.py && venv/bin/python -m pip install --upgrade pip pip-tools pipx; fi

pyenv-python:
	runmany 'pyenv install $$1' 2.7.18 3.9.1

pipx:
	@bin/fig pipx
	if ! test -x venv/bin/pipx; then \
		./env.sh venv/bin/python -m pip install --upgrade pip pip-tools pipx; fi
	bin/runmany 'venv/bin/python -m pipx install $$1' cookiecutter pre-commit yq keepercommander docker-compose black pylint flake8 isort pyinfra aws-sam-cli poetry solo-python ec2instanceconnectcli
	venv/bin/python -m pipx install --pip-args "httpie-aws-authv4" httpie
	venv/bin/python -m pipx install --pip-args "tox-pyenv tox-docker" tox
	venv/bin/python -m pipx install --pip-args "ansible" --force ansible-base

asdf:
	if [[ "$(shell id -un)" != "cloudshell-user" ]]; then bin/fig asdf; ./env.sh asdf install; fi

brew:
	-if test -x "$(shell which brew)"; then bin/fig brew; brew bundle; fi

brew-install:
	 curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh | bash -

misc:
	@bin/fig misc
	~/env.sh $(MAKE) /usr/local/bin/pinentry-defn
	~/env.sh $(MAKE) .config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator
	~/env.sh $(MAKE) bin/docker-credential-pass
	~/env.sh $(MAKE) /usr/local/bin/pass-vault-helper

.config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator:
	@bin/fig sops
	mkdir -p .config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator
	curl -o .config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator -sSL https://github.com/goabout/kustomize-sopssecretgenerator/releases/download/v1.3.2/SopsSecretGenerator_1.3.2_$(shell uname -s | tr '[:upper:]' '[:lower:]')_amd64
	-chmod 755 .config/kustomize/plugin/goabout.com/v1beta1/sopssecretgenerator/SopsSecretGenerator

/usr/local/bin/pinentry-defn:
	@bin/fig pinentry
	if [[ -w /usr/local/bin ]]; then \
		ln -nfs "$(HOME)/bin/pinentry-defn" /usr/local/bin/pinentry-defn; \
	else \
		sudo ln -nfs "$(HOME)/bin/pinentry-defn" /usr/local/bin/pinentry-defn; fi

bin/docker-credential-pass:
	@bin/fig pass-docker
	go mod init github.com/amanibhavam/homedir
	go get github.com/jojomomojo/docker-credential-helpers/pass/cmd@v0.6.5
	go build -o bin/docker-credential-pass github.com/jojomomojo/docker-credential-helpers/pass/cmd

/usr/local/bin/pass-vault-helper:
	@bin/fig pass-vault
	if [[ -w /usr/local/bin ]]; then \
		ln -nfs "$(HOME)/bin/pass-vault-helper" /usr/local/bin/pass-vault-helper; \
	else \
		sudo ln -nfs "$(HOME)/bin/pass-vault-helper" /usr/local/bin/pass-vault-helper; fi

ts-sync:
	sudo rsync -ia /mnt/tailscale/. /var/lib/tailscale/.
	sudo systemctl restart tailscaled
	$(MAKE) ts

ts-save:
	sudo rsync -ia /var/lib/tailscale/. /mnt/tailscale/.

ts:
	sudo tailscale up --accept-dns=false --accept-routes=true

multipass:
	brew install multipass
	brew install --cask slack virtualbox virtualbox-extension-pack

mp:
	m delete --all --purge
	$(MAKE) defn0
	rm -f .kube/config
	touch .kube/config
	bin/m-install-k3s defn0 defn
	kubectl config use-context defn
	$(MAKE) mp-cilium
	#kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/namespace.yaml
	#kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.6/manifests/metallb.yaml
	#kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$$(openssl rand -base64 128)"
	#km apply -f metal.yaml
	k apply -f nginx.yaml

mp-defn1:
	$(MAKE) defn1
	bin/m-join-k3s defn1 defn0

mp-cilium:
	kubectl create -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-install.yaml
	kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-hubble-install.yaml
	-while kubectl get nodes | grep NotReady; do sleep 10; done
	sleep 30
	while kubectl get nodes | grep NotReady; do sleep 10; done

mp-cilium-test:
	kubectl create ns cilium-test
	kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/v1.9/examples/kubernetes/connectivity-check/connectivity-check.yaml

mp-hubble-ui:
	kubectl port-forward -n kube-system svc/hubble-ui --address 0.0.0.0 --address :: 12000:80

mp-hubble-relay:
	kubectl port-forward -n kube-system svc/hubble-relay --address 0.0.0.0 --address :: 4245:80

mp-hubble-status:
	hubble --server localhost:4245 status

mp-hubble-observe:
	hubble --server localhost:4245 observe -f

defn0 defn1 defn2 defn3:
	-m delete $@
	m purge
	m launch -c 4 -d 100G -m 4096M --network en0 -n $@
	cat .ssh/id_rsa.pub | m exec $@ -- tee -a .ssh/authorized_keys
	m exec $@ git clone https://github.com/amanibhavam/homedir
	m exec $@ homedir/bin/copy-homedir
	m exec $@ -- sudo mount bpffs -t bpf /sys/fs/bpf
	mkdir -p ~/.config/$@/tailscale
	sudo multipass mount $$HOME/.config/$@/tailscale $@:/var/lib/tailscale
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | m exec $@ -- sudo apt-key add -
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.list | m exec $@ -- sudo tee /etc/apt/sources.list.d/tailscale.list
	m exec $@ -- sudo apt-get update
	m exec $@ -- sudo apt-get install tailscale
	m exec $@ -- sudo tailscale up
