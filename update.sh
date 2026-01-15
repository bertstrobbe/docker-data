#!/bin/bash
apt update
apt full-upgrade -y
apt autoremove -y

cd /home/bert/docker-data
docker compose pull
docker compose up -d
docker image prune -af
docker volume prune -f