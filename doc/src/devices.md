# Device pass-through

PCI and USB pass-through is supported on some hypervisors. Permission
setup is automatic for declared `"pci'` devices, but manual for
`"usb"` devices.

## Example PCI pass-through

Guest example:

```nix
microvm.devices = [ {
  bus = "pci";
  path = "0000:06:00.1";
} {
  bus = "pci";
  path = "0000:06:10.4";
} ];
```

Permission setup on the host is provided by systemd template unit
`microvm-pci-devices@.service`.

## Example USB pass-through

### In the guest

```nix
microvm.devices = [
  # RTL2838UHIDIR
  # Realtek Semiconductor Corp. RTL2838 DVB-T
  { bus = "usb"; path = "vendorid=0x0bda,productid=0x2838"; }
  # Sonoff Zigbee 3.0 USB Dongle Plus
  # Silicon Labs CP210x UART Bridge
  { bus = "usb"; path = "vendorid=0x10c4,productid=0xea60"; }
];
```

### On the host

USB device paths are not directly translatable to udev rules. Setup
permissions yourself:

```nix
services.udev.extraRules = ''
  # RTL2838UHIDIR
  # Realtek Semiconductor Corp. RTL2838 DVB-T
  SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="2838", GROUP="kvm"
  # Sonoff Zigbee 3.0 USB Dongle Plus
  # Silicon Labs CP210x UART Bridge
  SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", GROUP="kvm"
'';
```
