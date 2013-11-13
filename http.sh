#!/bin/bash

gor compile || exit
cp -r posts/img compiled
gor http
