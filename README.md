# Monarco HAT Flash Firmware Downloader

Firmware version history and roadmap: <https://github.com/monarco/monarco-hat-documentation/blob/master/Monarco_HAT_Firmware_Roadmap.md>


## Other Resources

* [Monarco Homepage - https://www.monarco.io/](https://www.monarco.io/)
* [Repository - Documentation for the Monarco HAT](https://github.com/monarco/monarco-hat-documentation)


## Usage

### Prepare Environment and Clone Repository

Install dependencies - on Debian/Raspbian:

```
$ sudo apt update
$ sudo apt install git perl-base libdigest-crc-perl libdevice-serialport-perl
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

and reboot to apply the settings.

### Flashing Firmware

Stop any application which use UART with the Monarco HAT (`/dev/ttyAMA0` on Raspberry Pi).
For example, the REX Control System `RexCore` service can be stopped by:

```
$ sudo service rexcore stop
```

Run firmware downloader with path to the most recent firmware image:

```
$ sudo ./monarco-flash.pl flash ./firmware-bin/fw-monarco-hat-2006.bin
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

CRC RESULT: [18] c--CRC: 00009C5C--

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


## Common Problems

Do not use GPIOs 0 (ID_SD), 1 (ID_SC), 2 (SDA), 3 (SCL), 8 (CE0), 9 (MISO), 10 (MOSI), 11 (SCLK), 14 (TXD), 15 (RXD), 20, 21, 26 for any custom applications with Monarco HAT! You could break correct operation of the Monarco HAT. Using colliding GPIOs can break the operation until complete power cycling is performed.  


## License

* `monarco-flash.pl` - BSD 3-Clause License - see LICENSE.txt
* firmware binary images under `firmware-bin/` - not open source, binary form can be redistributed without any restriction
* libraries under `libperl/` (`Fuser`, `Device::SerialPort::XModem`) - the same terms as Perl itself
