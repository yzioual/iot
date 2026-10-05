# -*- mode: ruby -*-
# vi: set ft=ruby :

# -------------------------------------------------------------
# Shell script: Server Provisioning
# -------------------------------------------------------------
$server_script = <<-SCRIPT
  set -e
  echo "[+] Updating system packages..."
  apt-get update -qq && apt-get install -y -qq curl

  echo "[+] Installing K3s Server..."
  # Bind K3s to the dedicated eth1 IP and tell Flannel to route through eth1
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --bind-address=192.168.56.110 \
    --node-ip=192.168.56.110 \
    --advertise-address=192.168.56.110 \
    --flannel-iface=eth1 \
    --write-kubeconfig-mode=644" sh -

  # Wait until the node token is generated
  while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    sleep 2
  done

  echo "[+] Exporting join token to /vagrant..."
  cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

  echo "[+] Setting up kubectl alias and environment for vagrant user..."
  echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.bashrc
SCRIPT

# -------------------------------------------------------------
# Shell script: Worker Provisioning
# -------------------------------------------------------------
$worker_script = <<-SCRIPT
  set -e
  echo "[+] Updating system packages..."
  apt-get update -qq && apt-get install -y -qq curl

  echo "[+] Waiting for node-token from server..."
  while [ ! -f /vagrant/node-token ]; do
    sleep 2
  done

  TOKEN=$(cat /vagrant/node-token)

  echo "[+] Installing K3s Worker (Agent)..."
  curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.110:6443" \
    K3S_TOKEN="${TOKEN}" \
    INSTALL_K3S_EXEC="agent \
      --node-ip=192.168.56.111 \
      --flannel-iface=eth1" sh -
SCRIPT

# -------------------------------------------------------------
# Vagrant Configuration
# -------------------------------------------------------------
Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  config.ssh.insert_key = true

  # Node 1: Controller / Server
  config.vm.define "yzioualS" do |server|
    server.vm.hostname = "yzioualS"
    server.vm.network "private_network", ip: "192.168.56.110"

    server.vm.provider "virtualbox" do |vb|
      vb.name = "yzioualS"
      vb.cpus = 1
      vb.memory = 1024
    end

    server.vm.provision "shell", inline: $server_script
  end

  # Node 2: Worker Node
  config.vm.define "yzioualSW" do |worker|
    worker.vm.hostname = "yzioualSW"
    worker.vm.network "private_network", ip: "192.168.56.111"

    worker.vm.provider "virtualbox" do |vb|
      vb.name = "yzioualSW"
      vb.cpus = 1
      vb.memory = 1024
    end

    worker.vm.provision "shell", inline: $worker_script
  end
end
