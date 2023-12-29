# Shell scripts

A set of somewhat useful shell scripts.

Initially it was written for Korn Shell (`ksh88`) for IBM AIX operating system,
but is expected to work with Bash and Linux as well.

The structure of the repository:

- `bin` directory contains scripts executables
- `lib` directory contains library files sourced by those executables
- `etc` directory contains configuration files samples

The scripts are:

- `cfbackup.sh` Backup configuration files and report differences
- `delcore.sh` Delete core files
- `nmon-collect.sh` Run NMON statistics collection
- `nmon-cleanup.sh` Clean up old NMON statistics
- `sysexec.sh` Execute commands on remote host

### ToDo

- Explain scripts usage and invocation
- Explain installation and configuration
