cat << EOF > /etc/apt/sources.list.d/eholnk.list
deb http://deb.debian.org/debian/ bookworm main non-free contrib
deb-src http://deb.debian.org/debian/ bookworm main non-free contrib

deb http://security.debian.org/debian-security bookworm-security main
deb-src http://security.debian.org/debian-security bookworm-security main

# bullseye-updates, to get updates before a point release is made;
# see https://www.debian.org/doc/manuals/debian-reference/ch02.en.html#_updates_and_backports
deb http://deb.debian.org/debian/ bookworm-updates main
deb-src http://deb.debian.org/debian/ bookworm-updates main

EOF
sed -i s:^deb:#deb: /etc/apt/sources.list

apt update && apt dist-upgrade -y && apt install build-essential dkms libelf-dev
apt purge linux-image-6.0.0-6-amd64 linux-image-5.19.0-1-amd64

cat << EOF > /etc/udev/rules.d/60-cas-scheduler.rules
ACTION=="add|change", KERNEL=="cas[1-9]-[1-9]", ATTR{queue/rotational}="0", ATTR{queue/scheduler}="deadline"
EOF

# Configure LVM to accept CAS
mv /etc/lvm/lvm.conf /etc/lvm/lvm.conf.backup
cat << EOF > /etc/lvm/lvm.conf
config {
}
devices {
	filter = [ "a|cas.*|","r|sd.*|"]
	types = [ "cas" , 16 ]
}
allocation {
}
log {
}
backup {
}
shell {
}
global {
}
activation {
}
dmeventd {
}
EOF

cat << EOF > opencas_drive45.csv
IO class id,IO class name,Eviction priority,Allocation
0,unclassified,22,1
1,metadata&done,0,1
11,file_size:le:4096&done,9,1
12,file_size:le:16384&done,10,1
13,file_size:le:65536&done,11,1
14,file_size:le:262144&done,12,1
15,file_size:le:1048576&done,13,1
16,file_size:le:4194304&done,14,1
17,file_size:le:16777216&done,15,1
18,file_size:le:67108864&done,16,1
19,file_size:le:268435456&done,17,1
20,file_size:le:1073741824&done,18,1
21,file_size:gt:1073741824&done,19,1
22,direct&done,20,1
EOF



#lvremove CACHE/CAS -y ; for i in $(seq 0 7); do lvremove CACHE/DB$i -y ; lvremove CACHE/WAL$i -y ; lvremove DATA${i}/BLOCK -y ; vgremove DATA$i -y ; done ; vgremove CACHE -y
wipefs -af /dev/nvme0n1
udevadm trigger
pvcreate /dev/nvme0n1 
vgcreate CACHE /dev/nvme0n1 
for i in $(seq 0 7)
do
lvcreate CACHE --size 2G -n WAL${i}
lvcreate CACHE --size 98G -n DB${i}
done
lvcreate CACHE --size 950G -n OPENCAS

cat << EOF > /etc/opencas/opencas.conf
version=19.3.0
[caches]
1 /dev/disk/by-id/dm-name-CACHE-OPENCAS WB ioclass_file=/etc/opencas/opencas_drive45.csv

[cores]
EOF
index=1
for drive in $(ls /dev/disk/by-id/wwn-0x5*)
do
echo "1		$index		$drive" >> /etc/opencas/opencas.conf
index=$((index+1))
done

echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC6MiFsULPKVlWGBQYFm3+uVbEMAcu3lA2RbdxJqgb1tgHh0gM8ImU7Bkza0zfoBMQoYMdLBUQsvtO6ewRmecNFIoD7zMTDxkZ0kKGqi+yiAGurKDzJeJzfWQHcPyHbI057YR3g5TpfoUOsUwJt6LFBDdmOOj0AGK9I2Egq9kIFcPG+JwWJz82nuqvwiMiunIQKkEn3xc/0K1MoxqJY8i02Lpmk7NImUQfURZpnG6NgNTMT8QZEtd36zYm4w+pkteFaCoPfz6aW1psXRY5A9EvSp+C6sr049Mh+YYMGKwfN0uOaaHn+CETxrbpV6i1rT2MQW47B0md0PhhdnuSFn1GCAQlO5PobrhEGC6U97hLCpgIp/5aUpzeUOCYFwOSeLhYnX7+YIB4v1+XWjIScAdeXdfDOM9grYlFVc7tGLhraJydR6l1r4GaozEQfqpPu3KTz6flOh/6mPvn6lO6VAnuoDE9QCjfJss4fZWqMYzlk0tWJ4ozTZGaDPMMf0BrXiB0= ceph-7a798416-7bb1-11ed-a89f-84160caa7828
" >> /root/.ssh/authorized_keys

instance=3
for i in $(seq 0 7);
do
cat << EOF > cas1-$((i+1))_debian${instance}.yaml
service_type: osd
service_id: osd_using_paths
placement:
  hosts:
    - debian${instance}
data_devices:
  paths:
    - /dev/cas1-$((i+1))/BLOCK
db_devices:
  paths:
    - /dev/CACHE/DB${i}
wal_devices:
  paths:
    - /dev/CACHE/WAL${i}
EOF
ceph orch apply osd -i ./cas1-$((i+1))_debian${instance}.yaml
sleep 60
done

apt install libelf-dev
