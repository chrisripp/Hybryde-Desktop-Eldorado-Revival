#! /bin/bash

gnome-tweak-tool ;

pid=$(pidof nautilus)

kill -9 $pid

nautilus --no-default-window &

exit
