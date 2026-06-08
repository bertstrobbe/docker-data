#!/bin/bash
#
# TIJDELIJKE safeguard tijdens de gefaseerde Geoapify reverse-geocoding backfill.
# dawarich heeft een ingebouwde nightly cron (Points::NightlyReverseGeocodingJob,
# 01:15) die ALLE niet-geocodeerde punten in 1x naar de provider dumpt. Tegen
# Geoapify's gratis 3k/dag-limiet is dat te veel. We hebben hem runtime-disabled,
# maar een herstart van dawarich herlaadt config/schedule.yml en zet hem terug
# op 'enabled'. Deze guard her-disablet hem elke dag om 01:00 (vlak vóór 01:15).
#
# >>> VERWIJDER dit script + de crontab-regel + RE-ENABLE de nightly job zodra de
#     backfill klaar is (geen punten meer zonder data). <<<
#
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
docker exec dawarich_app bin/rails runner \
  "require 'sidekiq/api'; Sidekiq::Cron::Job.find('nightly_reverse_geocoding_job')&.disable!; \
   puts 'nightly_status=' + Sidekiq::Cron::Job.find('nightly_reverse_geocoding_job')&.status.to_s" \
  2>&1 | grep -i 'nightly_status'
echo "$(date '+%Y-%m-%d %H:%M') guard ran"
