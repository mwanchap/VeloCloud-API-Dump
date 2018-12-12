from __future__ import print_function
import velocloud
from velocloud.rest import ApiException
import velocloud_lookups
from velocloud_lookups import appsLookup, catergoryLookup
import datetime
from datetime import datetime, timedelta
import csv
import string

def Write_CSV(filename, fields, data):
    "Used to output CSVs once all the data has been retrieved"
    # dialect = csv.Dialect()
    # dialect.lineterminator = '\n'
    with open("Output/"+filename, mode='w') as output_file:
        csv_writer = csv.DictWriter(output_file,fieldnames = fields, dialect='unix', delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)
        csv_writer.writeheader()

        for row in data:
            csv_writer.writerow(row)

def Format_Usage(usage):
    "Returns data usage in bytes, formatted nicely for readability"
    return str(round(usage / 1000 / 1000, 5))

def Format_Bandwidth(bandwidth):
    "Returns bandwidth in bytes, formatted nicely for readability"
    return str(round(bandwidth / 1000 / 1000, 5)) + " Mbps"

def Get_App_Name(app_id):
    "Returns the name of an app for a given app Id"
    app_name = ""
    try:
        app_name = appsLookup[app_id]
    except:
        app_name = "Unknown"
    return app_name

def Get_Catergory_Name(cat_id):
    "Returns the name of an Catergory for a given Catergory Id"
    cat_name = ""
    try:
        cat_name = catergoryLookup[cat_id]
    except:
        cat_name = "Unknown"
    return cat_name

# If SSL verification disabled (e.g. in a development environment)
import urllib3
urllib3.disable_warnings()
velocloud.configuration.verify_ssl=False

# connection vars
host = "velocloud hostname goes here"
username = "username goes here"
password = "password goes here"

# if you need to proxy this, set proxy in \sdk\python\velocloud\rest.py:89
client = velocloud.ApiClient(host)
client.authenticate(username, password, operator=False)
api = velocloud.AllApi(client)

# calculate report date range - it's a unix epoch timestamp calculated relative to UTC
epoch = datetime.utcfromtimestamp(0)

# minus 10 hours from date ranges for QLD AUS time  UTC -10
StartDate = (datetime(2018,12,2,14,0) - epoch).total_seconds() *1000
EndDate = (datetime(2018,12,9,14,00) - epoch).total_seconds() *1000
reportInterval =  {"start": StartDate,"end": EndDate}

# or to just get the last 7 days:
# startTime = datetime.utcnow() - timedelta(days=7)
# utcTimeStamp = int((startTime - epoch).total_seconds() * 1000)
# reportInterval =  {"start": utcTimeStamp}

# storing edge data in this dictionary
edgeTotalUsage = []

# query enterprise info and list of edges
enterprise = api.enterpriseGetEnterprise({})
edges = api.enterpriseGetEnterpriseEdges(enterprise.id)
total_edges = len(edges)

# loop through all the edges and get data for each one
for edge_num, edge in enumerate(edges):

    progress = round(((edge_num + 1) / total_edges) * 100, 2)
    print(f"Processed {progress}% - edge ({edge_num+1}/{total_edges}) {edge.name} (edge {edge.id})")
    totalData = 0

    # strip non-alphanumeric characters from the edge name to make a valid windows filename        
    edgeCleanName = str.join("", list(filter(str.isalnum, edge.name)))

    queryParams = {
        "id": edge.id,
        "interval": reportInterval
    }

    # query usage for each app in this edge
    edgeAppMetricsResult = api.metricsGetEdgeAppMetrics(queryParams)

    # reset app usage for each edge
    edgeAppUsage = []

    for appMetric in edgeAppMetricsResult:
        totalData += appMetric.totalBytes
        edgeAppUsage.append({
            "edgename": edge.name,
            "appname": Get_App_Name(appMetric.name),
            "usage (MB)": Format_Usage(appMetric.totalBytes)
        })


    Write_CSV(
        filename = f"App usage - {edgeCleanName}.csv",
        fields = ['edgename', 'appname', 'usage (MB)'],
        data = edgeAppUsage)

    edgeTotalUsage.append({
        "name": edge.name,
        "usage (MB)": Format_Usage(totalData)
    })

    # query usage for each link in this edge (to get bandwidth etc)
    edge_link_metrics = api.metricsGetEdgeLinkMetrics(queryParams)
    edge_link_data = []

    for link_metric in edge_link_metrics:
        edge_link_data.append({
            "edgename": edge.name,
            "linkname": link_metric.link.displayName,
            "linktype": link_metric.name,
            "bandwidth_rec": Format_Bandwidth(link_metric.bpsOfBestPathRx),
            "bandwidth_trans": Format_Bandwidth(link_metric.bpsOfBestPathTx)
        })

    Write_CSV(
        filename = f"Link bandwidth - {edgeCleanName}.csv",
        fields = ['edgename', 'linkname', 'linktype', 'bandwidth_rec', 'bandwidth_trans'],
        data = edge_link_data)

    # query usage for each device in this edge
    edgeDeviceMetricsResult = api.metricsGetEdgeDeviceMetrics(queryParams)
    edgeDeviceUsage = []
    edgeDeviceAppUsage = []
    total_device_data = 0.0
    
    for device in edgeDeviceMetricsResult:
        total_device_data += device.totalBytes
        edgeDeviceUsage.append({
            "edgename": edge.name,
            "devicename": device.info.hostName,
            "usage (MB)": Format_Usage(device.totalBytes)
        })

        # query usage for each app for this device
        queryFilters = [{
            "field":"device",
            "op":"=",
            "values":[device.name]
        }]

        queryParams["filters"] = queryFilters
        deviceAppMetricsResult = api.metricsGetEdgeAppMetrics(queryParams)
        total_device_app_data = 0.0

        for deviceApp in deviceAppMetricsResult:
            total_device_app_data += deviceApp.totalBytes
            edgeDeviceAppUsage.append({
                "edgename": edge.name,
                "devicename": device.info.hostName,
                "appname": Get_App_Name(deviceApp.application),
                "category": Get_Catergory_Name(deviceApp.category),
                "usage (MB)": Format_Usage(deviceApp.totalBytes)
            })

    Write_CSV(
        filename = f"Device usage - {edgeCleanName}.csv",
        fields = ['edgename', 'devicename', 'usage (MB)' ],
        data = edgeDeviceUsage)

    Write_CSV(
        filename = f"Device App usage - {edgeCleanName}.csv",
        fields = ['edgename', 'devicename', 'appname', 'category', 'usage (MB)'],
        data = edgeDeviceAppUsage)
# end of edges loop

# write out summary data
Write_CSV(
    filename = 'Edge Usage Summaries.csv',
    fields = ['name', 'usage (MB)'],
    data = edgeTotalUsage)
