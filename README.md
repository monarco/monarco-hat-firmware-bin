# Monarco HAT Flash Firmware Downloader

## Usage

### Prepare Environment and Clone Repository

Install dependencies - on Debian/Raspbian:

```
$ sudo apt update
$ sudo apt install git perl libdigest-crc-perl libdevice-serialport-perl
```

Clone repository:

```
$ git clone https://github.com/monarco/monarco-hat-firmware-bin
$ cd monarco-hat-firmware-bin
```

Disable Linux console on UART - on Raspberry Pi edit `/boot/cmdline.txt`:

```
$ sudo sed 's/ console=serial0,[0-9]\+//' -i /boot/cmdline.txt
```

### Flashing Firmware

Stop any application which use UART with the Monarco HAT (`/dev/ttyAMA0` on Raspberry Pi).
For example, the REX Control System `RexCore` service can be stopped by:

```
$ sudo service rexcore stop
```

Run firmware downloader with path to the most recent firmware image:

```
$ sudo ./monarco-flash.pl flash ./firmware-bin/fw-monarco-hat-2004.bin
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

HAT ID detected:
  Vendor: REX Controls
  Product: Monarco HAT
  Product ID: 0x0001
  Product VER: 0x0103
  UUID: fe0f39bf-7c03-4eb6-9a91-df861ae5abcd

Serial device /dev/ttyAMA0 check OK.

MCU Bootloader ID: [1.60 ChipID: 247DBC0257516B45]

Press ENTER to continue ...
XModem: Start, waiting for handshake
XModem: Handshake success
XModem: Sending: .................................................................................................................................................................

CRC RESULT: [18] c--CRC: 0000BB5C--

OK!
```

### Quick Help

```
$ sudo ./monarco-flash.pl
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

Usage:
    ./monarco-flash.pl [options] flash <firmware-image-file>
    ./monarco-flash.pl [options] getserial

Options defaults: --uart_device=/dev/ttyAMA0 --gpio_reset=21 --gpio_bootloader=20
```

### Checking Monarco HAT MCU ID

```
$ sudo ./monarco-flash.pl getserial
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

MCU Bootloader ID: [1.60 ChipID: 247DBC0257516B45]
```

## Runtime Requirements

Debian packages:

* `perl`
* `libdigest-crc-perl`
* `libdevice-serialport-perl`
