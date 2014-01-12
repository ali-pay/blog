#!/bin/bash

gor compile && \
cp -r posts/img compiled && \
cp -r compiled/* /var/www/nuodami.cn

