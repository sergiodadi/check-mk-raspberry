# check-mk-raspberry
Checkmk for Raspberry Pi (buster 32 bits and bulleyes 64 bits)

The sources of Checkmk can be found here: https://github.com/tribe29/checkmk

first, thanks to [chriss404](https://github.com/chrisss404/check-mk-arm) :+1:, we only build somes packages with the chriss404 scripts.
We use his tool to build some packages not available:

- check-mk for Raspberry buster 32 bits **armhf** (from 2.0.0p17) 
- check-mk for Raspberry bulleyes 64 bits **arm64** (from 2.0.0p21) [not available now, work in progress]

On the release page you can find deb packages targeting the following systems:
- Raspberry Pi OS buster 32 bits (**armhf**)

I have tested the buster  *2.0.0p21* package on a **Raspberry PI 4 - 4 Gb** : ARMv7 Processor rev 3 (v7l)

