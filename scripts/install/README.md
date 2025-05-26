# Docker Installation Script

This script provides an automated way to install Docker and optionally Portainer on supported Linux distributions. It includes error handling, OS detection, and a user-friendly interface.

## Features

- 🐳 Automatic Docker installation
- 🔍 OS detection and support for multiple distributions
- 🎨 Colored output for better readability
- 🔒 Root permission checking
- 🔄 Optional Portainer installation
- ✅ Installation verification
- 🛡️ Error handling and logging

## Supported Operating Systems

- Ubuntu
- Debian
- Alpine Linux

## Prerequisites

- Root privileges (sudo access)
- Internet connection
- Supported Linux distribution

## Usage

1. Download the script:

   ```bash
   wget https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/install/docker.sh
   ```

2. Make the script executable:

   ```bash
   chmod +x install.sh
   ```

3. Run the script with sudo:
   ```bash
   sudo ./install.sh
   ```

## What the Script Does

1. **System Checks**:

   - Verifies root privileges
   - Detects the operating system
   - Checks for existing Docker installation

2. **Docker Installation**:

   - Removes old Docker versions (if present)
   - Installs required dependencies
   - Adds Docker's official GPG key
   - Sets up Docker repository
   - Installs Docker and Docker Compose

3. **Verification**:

   - Starts Docker service
   - Runs hello-world container to verify installation
   - Displays Docker and Docker Compose versions

4. **Optional Portainer Installation**:
   - Prompts user for Portainer installation
   - Creates necessary volumes
   - Sets up Portainer with default configuration

## Portainer Access

If you choose to install Portainer, you can access it at:

- HTTP: http://localhost:8000
- HTTPS: https://localhost:9443

## Error Handling

The script includes comprehensive error handling for:

- Missing root privileges
- Unsupported operating systems
- Failed Docker installation
- Failed Portainer installation
- Network connectivity issues

## Logging

The script provides colored output for different types of messages:

- 🟢 Green: Information messages
- 🟡 Yellow: Warnings
- 🔴 Red: Error messages

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

If you encounter any issues or have questions, please open an issue in the repository.
