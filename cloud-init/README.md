# Cloud-init user-data for Brother HL-4570CDW

This `user-data` installs CUPS and repackages the HL-4570CDW drivers using
`alexivkin/brother-in-arms`, then optionally configures the printer.

## Use

1. Copy `cloud-init/user-data.yaml` to the `user-data` file on the FAT boot
   partition of your Raspberry Pi OS image.
2. (Optional) Edit the hostname in the YAML.
3. (Optional) Set a printer URI and PPD path after first boot.

## Optional printer setup

If you want `lpadmin` to configure the printer automatically, set these
environment variables and re-run the installer on the Pi:

```
export PRINTER_URI='socket://<printer-ip>:9100'
export PRINTER_NAME='BrotherHL4570CDW'
export PPD_PATH='<ppd-from-lpinfo>'
sudo /usr/local/sbin/install-brother-drivers 'HL-4570CDW'
```

To discover the available PPDs:

```
lpinfo -m | grep -i hl4570
```

## Notes

- On 64-bit Raspberry Pi OS, the script adds `armhf` and installs `libc6:armhf`.
- The installer uses `oh_brother.zsh` from the repo and patches the final
  `systemctl restart cups` to be non-fatal in non-systemd containers.
