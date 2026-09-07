# Security policy

## Reporting a vulnerability

Do not open a public issue for a vulnerability that exposes credentials, private network information or unauthorized device control. Contact the repository owner privately through their published GitHub contact method.

## Local-network considerations

The legacy Daikin API uses unencrypted HTTP on the local network and may expose device and network identifiers through `/common/basic_info`. Use the adapter only on a trusted home network or isolated IoT VLAN.

This driver:

- communicates only with the configured or discovered LAN host;
- does not require an ONecta account or cloud token;
- does not log complete API responses;
- does not embed device IDs, MAC addresses, SSIDs or credentials.

Users should keep their router, SmartThings hub and Daikin adapter firmware maintained and should block untrusted clients from the IoT network.
