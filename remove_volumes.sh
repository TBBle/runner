#!/bin/bash

docker volume rm $(docker volume ls --quiet --filter 'name=cyber_dojo_')