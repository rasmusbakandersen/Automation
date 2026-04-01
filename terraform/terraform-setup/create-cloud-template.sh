qm create 9000 --name fedora-cloud-template --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 --ostype l26
qm set 9000 --scsihw virtio-scsi-single \
  --scsi0 local-lvm:0,import-from=/mnt/pve/SanxerNas/template/iso/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
