# Configuration options

By including the `microvm` module a set of NixOS options is made
available for customization. These are the most important ones:

| Option               | Purpose                                                  |
|----------------------|----------------------------------------------------------|
| `microvm.hypervisor` | Hypervisor to use by default in `microvm.declaredRunner` |
| `microvm.vcpu`       | Number of Virtual CPU cores                              |
| `microvm.mem`        | RAM allocation in MB                                     |
| `microvm.interfaces` | Network interfaces                                       |
| `microvm.volumes`    | Block device images                                      |
| `microvm.shares`     | Shared filesystem directories                            |
