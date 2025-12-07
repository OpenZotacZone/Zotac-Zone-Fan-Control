# Zotac ZONE Fan Control
[![OpenZONE Discord](https://img.shields.io/badge/Discord-%235865F2.svg?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/YFhK768cex)

Install script for Bazzite/Fedora Atomic based distributions

## Description
Take control of your Zotac Gaming Zone fan by adjusting the fan curves.
This script installs CoolerControl the "Zotac ZONE EC fan driver" by ElektroCoder automatically.
It is intended to simplify the steps described in the [GIST provided by ElektroCoder](https://gist.github.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74) and to make the installation more userfriendly.

## Setup
1. Download install_zotac_fan.sh
2. Open a terminal in the folder where the file is located by right clicking and selecting "open terminal here" in KDE
3. Make the file executable by running this:
   
   `chmod +x install_zotac_fan.sh`
   
5. Run the script with sudo:
   
   `sudo ./install_zotac_fan.sh`
   
7. Enter your admin password
8. When the script is finished installing CoolerControl, it will prompt you to restart the system by rebooting the device
9. After the restart, run the script again to finish the installation:
    
    `sudo ./install_zotac_fan.sh`

10. If the installation was succesfull, open the CoolerControl UI by opening [http://localhost:11987](http://localhost:11987) in your browser

## Configuring your fan curve

1. To configure the fan curve, open CoolerControl in your browser
2. In the left menu, click on "Control" and select Fan1 under "zotac_platform"
3. Select "Create a new profile"
4. Give it any name and choose "Graph" as type
5. Select "CPU Temp Tctl" under "AMD Ryzen 7 8840U w/ Radeon 780M Graphics" as your temperature source
6. Configure the curve to your liking and select "Default Function"
7. Save the profile

_Thats it! Now enjoy a much quieter gaming experience without your fan spinning up and down every few seconds!_


## Credits
-  [ElektroCoder](https://gist.github.com/ElektroCoder/) for providing the EC fan driver
