# VeloCloud-API-Dump
Uses VeloCloud's API to dump out a bunch of CSVs containing all the edge/app/device usage data.

Usage:
 - Get a computer and install Python 3 on it
 - Download and unzip the VeloCloud API stuff somewhere (it's confidential so I can't include it)
 - Open a terminal, cd over to that place, `python -m pip install -r requirements.txt`
 - In export-velocloud-data.py, replace the host, username and password vars with the relevant values for your VeloCloud instance
 - Also fix up the date vars, I'm in the UTC+10 TZ so I just subtracted 10 from the start/end dates I wanted
 - Create a folder called "output" in the same dir as export-velocloud-data.py for it to save all its output
 - Run it and find something else to do for a while, the instance I was using took like an hour to export all the data

Data transfer values are formatted in MB and rounded off, so you'll probably want to remove calls to Format_Usage if you want to do BI things with the output.

Future improvement (PRs super welcome!):
 - Do API calls asynchronously or in batches, maybe get multiple edges/apps/devices at once
 - Output into spreadsheets as well as CSVs
 - Replace velocloud_lookups.py with something generating enums from https://sdn.macquarieview.com/vco/enums.js , since VeloCloud don't seem to provide an API endpoint to enumerate that stuff
 - Refactor into something a bit tidier
 - Fix the typos
 - Rewrite to use more idiomatic python_variable_names rather than being mostly camelCase
 - Combine Format_Usage and Format_Bandwidth
 - Combine Get_App_Name and Get_Catergory_Name [sic]

To set this up on an EC2 instance
- `sudo yum -y update`
- `sudo yum install python36` or alternatively try [this](https://stackoverflow.com/a/48314242/2939759)
- `sudo python36 -m pip install --upgrade pip`
- `sudo python36 -m pip install -r requirements.txt`
- `python36 export-velocloud-data.py`

