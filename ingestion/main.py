import os
import time
from datetime import datetime, timedelta
from collections import defaultdict
from google.cloud import monitoring_v3
from google.cloud import bigquery

# Environment Variables
PROJECT_ID = os.environ.get("PROJECT_ID")
BQ_DATASET = os.environ.get("BQ_DATASET", "oncall_health")
BQ_TABLE = os.environ.get("BQ_TABLE", "raw_metrics")

def fetch_and_write_metrics(request):
    """
    Cloud Function entry point for ingesting Data Commons metrics via Cloud Monitoring.
    Triggered daily by Cloud Scheduler.
    """
    monitoring_client = monitoring_v3.MetricServiceClient()
    bq_client = bigquery.Client()
    
    # We will use the caller's project as the scoping project 
    project_name = f"projects/{bq_client.project}"
    
    # Calculate the time window for strictly yesterday (00:00:00 to 00:00:00 UTC)
    import calendar
    today = datetime.utcnow().date()
    yesterday = today - timedelta(days=1)
    
    start_dt = datetime(yesterday.year, yesterday.month, yesterday.day, 0, 0, 0)
    end_dt = datetime(today.year, today.month, today.day, 0, 0, 0)
    
    start_seconds = calendar.timegm(start_dt.timetuple())
    end_seconds = calendar.timegm(end_dt.timetuple())

    interval = monitoring_v3.TimeInterval(
        {
            "start_time": {"seconds": start_seconds, "nanos": 0},
            "end_time": {"seconds": end_seconds, "nanos": 0},
        }
    )

    metrics_by_service = defaultdict(lambda: {"total_requests": 0, "error_requests": 0, "p50_ms": None, "p95_ms": None, "project_id": "unknown"})

    METRIC_SOURCES = [
        {
            "counts": 'metric.type="run.googleapis.com/request_count"',
            "latency": 'metric.type="run.googleapis.com/request_latencies"',
            "service_label": "service_name",
            "prefix": "cloudrun"
        },
        {
            "counts": 'metric.type="loadbalancing.googleapis.com/https/request_count"',
            "latency": 'metric.type="loadbalancing.googleapis.com/https/backend_latencies"',
            "service_label": "backend_service_name",
            "prefix": "gke-lb"
        },
        {
            "counts": 'metric.type="serviceruntime.googleapis.com/api/request_count"',
            "latency": 'metric.type="serviceruntime.googleapis.com/api/request_latencies"',
            "service_label": "service",
            "prefix": "endpoints"
        },
        {
            "counts": 'metric.type="apigee.googleapis.com/proxyv2/request_count"',
            "latency": 'metric.type="apigee.googleapis.com/proxyv2/total_response_time"',
            "service_label": "proxy",
            "prefix": "apigee"
        }
    ]

    for source in METRIC_SOURCES:
        # A. Fetch Request Counts
        count_aggregation = monitoring_v3.Aggregation(
            alignment_period={"seconds": 86400},
            per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_DELTA,
            cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_SUM,
            group_by_fields=[f"resource.labels.{source['service_label']}", "metric.labels.response_code_class"]
        )
        try:
            count_results = monitoring_client.list_time_series(
                request={
                    "name": project_name,
                    "filter": source["counts"],
                    "interval": interval,
                    "aggregation": count_aggregation,
                }
            )
        except Exception as e:
            print(f"Skipping {source['counts']} due to error: {e}")
            count_results = []
        for result in count_results:
            raw_name = result.resource.labels.get(source['service_label'])
            if not raw_name: continue
            if source['prefix'] == 'endpoints' and raw_name.endswith('.googleapis.com'): continue
            
            # Prefix the service to easily distinguish GKE vs Cloud Run in the DB
            service_name = f"{source['prefix']}--{raw_name}"
            response_class = result.metric.labels.get("response_code_class", "2xx")
            
            if result.points:
                val = result.points[0].value.int64_value
                metrics_by_service[service_name]["total_requests"] += val
                if result.resource.labels.get("project_id"):
                    metrics_by_service[service_name]["project_id"] = result.resource.labels.get("project_id")
                if str(response_class).startswith("5"):
                    metrics_by_service[service_name]["error_requests"] += val

        # B. Fetch P50 Latency
        p50_aggregation = monitoring_v3.Aggregation(
            alignment_period={"seconds": 86400},
            per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_PERCENTILE_50,
            cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_PERCENTILE_50,
            group_by_fields=[f"resource.labels.{source['service_label']}"]
        )
        try:
            p50_results = monitoring_client.list_time_series(
                request={
                    "name": project_name,
                    "filter": source["latency"],
                    "interval": interval,
                    "aggregation": p50_aggregation,
                }
            )
        except Exception as e:
            print(f"Skipping P50 {source['latency']} due to error: {e}")
            p50_results = []
        for result in p50_results:
            raw_name = result.resource.labels.get(source['service_label'])
            if source['prefix'] == 'endpoints' and raw_name and raw_name.endswith('.googleapis.com'): continue
            if raw_name and result.points:
                service_name = f"{source['prefix']}--{raw_name}"
                val = result.points[0].value.double_value
                if source['prefix'] == 'endpoints': 
                    val *= 1000.0
                metrics_by_service[service_name]["p50_ms"] = val

        # C. Fetch P95 Latency
        p95_aggregation = monitoring_v3.Aggregation(
            alignment_period={"seconds": 86400},
            per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_PERCENTILE_95,
            cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_PERCENTILE_95,
            group_by_fields=[f"resource.labels.{source['service_label']}"]
        )
        try:
            p95_results = monitoring_client.list_time_series(
                request={
                    "name": project_name,
                    "filter": source["latency"],
                    "interval": interval,
                    "aggregation": p95_aggregation,
                }
            )
        except Exception as e:
            print(f"Skipping P95 {source['latency']} due to error: {e}")
            p95_results = []
        for result in p95_results:
            raw_name = result.resource.labels.get(source['service_label'])
            if source['prefix'] == 'endpoints' and raw_name and raw_name.endswith('.googleapis.com'): continue
            if raw_name and result.points:
                service_name = f"{source['prefix']}--{raw_name}"
                val = result.points[0].value.double_value
                if source['prefix'] == 'endpoints': 
                    val *= 1000.0
                metrics_by_service[service_name]["p95_ms"] = val

    # Format for BigQuery
    metrics_data = []
    timestamp_now = datetime.utcnow().isoformat()
    target_date = yesterday.strftime('%Y-%m-%d')
    for service, agg in metrics_by_service.items():
        if agg["total_requests"] == 0:
            availability = 1.0 # 100% if no traffic
        else:
            availability = (agg["total_requests"] - agg["error_requests"]) / agg["total_requests"]
            
        metrics_data.append({
            "timestamp": timestamp_now,
            "target_date": target_date,
            "project_id": agg["project_id"],
            "service_name": service,
            "archetype": "sync", # Assuming all Cloud Run deployments are sync archetypes
            "availability_ratio": round(availability, 4),
            "total_requests": agg["total_requests"],
            "error_requests": agg["error_requests"],
            "latency_p50_ms": round(agg["p50_ms"], 2) if agg["p50_ms"] else None,
            "latency_p95_ms": round(agg["p95_ms"], 2) if agg["p95_ms"] else None
        })

    if metrics_data:
        table_id = f"{bq_client.project}.{BQ_DATASET}.{BQ_TABLE}"
        print(f"Streaming {len(metrics_data)} rows to {table_id}...")
        try:
            errors = bq_client.insert_rows_json(table_id, metrics_data)
            if errors:
                print(f"Encountered errors writing to BigQuery: {errors}")
                return f"Errors: {errors}", 500
        except Exception as e:
            print(f"BigQuery output failed: {e}")
            return f"BigQuery Error: {e}", 500
            
    return "Metrics ingested successfully", 200

# For local testing
if __name__ == "__main__":
    fetch_and_write_metrics(None)
