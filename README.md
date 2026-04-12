Klipper on Snapmaker J1/J1s

# Build images

- Install prerequisites like docker, build tools and cross compiler for arm-none-eabi for your Linux installation
- Create empty directory `mkdir mybuild` and change into it `cd mybuild`
- Call build/build.sh from your empty directory `bash ../build/build.sh`

If it works you should get 4 images in your build directory:
- lk2nd.img & mainsailos.img are needed for the Snapamaker J1 
- lk2nd-fastboot.img is a variant which waits 5 min for fastboot commands like `fastboot oem reboot-edl`
- armbian.img is an intermediate required for MainsailOS