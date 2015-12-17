#!/bin/bash

#rsync -avzr compiled/* dg:/var/www/.nuomi-studio/
./build.sh && cd compiled && git add * && git commit -am "update `LANG=C date`" && git push

