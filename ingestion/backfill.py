import os
import calendar
from datetime import datetime, timedelta
from collections import defaultdict
from google.cloud import monitoring_v3
from google.cloud import bigquery

PROJECT_ID = os.environ.get("PROJECT_ID", "datcom-ci")
BQ_DATASET = os.environ.get("BQ_DATASET", "oncall_health")
BQ_TABLE = os.environ.get("BQ_TABLE", "raw_metrics")

def backfill(start_days_ago=1, end_days_ago=51):
    monitoring_client = monitoring_v3.MetricServiceClient()
    bq_client = bigquery.Client(project=PROJECT_ID)
    project_name = f"projects/{PROJECT_ID}"
    
    METRIC_SOURCES = [
        {"counts": 'metric.type="run.googleapis.com/request_count"', "latency": 'metric.type="run.googleapis.com/request_latencies"', "service_label": "service_name", "prefix": "cloudrun"},
        {"counts": 'metric.type="loadbalancing.googleapis.com/https/request_count"', "latency": 'metric.type="loadbalancing.googleapis.com/https/backend_latencies"', "service_label": "backend_service_name", "prefix": "gke-lb"},
        {"counts": 'metric.type="serviceruntime.googleapis.com/api/request_count"', "latency": 'metric.type="serviceruntime.googleapis.com/api/request_latencies"', "service_label": "service", "prefix": "endpoints"},
        {"counts": 'metric.type="apigee.googleapis.com/proxyv2/request_count"', "latency": 'metric.type="apigee.googleapis.com/proxyv2/total_response_time"', "service_label": "proxy", "prefix": "apigee"}
    ]

    print(f"Starting backfill from {start_days_ago} days ago to {end_days_ago} days ago...")
    
    # Loop continuously backwards in time
    for days_ago in range(start_days_ago, end_days_ago + 1):
        target_date_obj = datetime.utcnow().date() - timedelta(days=days_ago)
        target_date_str = target_date_obj.strftime('%Y-%m-%d')
        print(f"\nProcessing: {target_date_str}...")

        start_dt = datetime(target_date_obj.year, target_date_obj.month, target_date_obj.day, 0, 0, 0)
        end_dt = start_dt + timedelta(days=1)
        
        interval = monitoring_v3.TimeInterval({
            "start_time": {"seconds": calendar.timegm(start_dt.timetuple()), "nanos": 0},
            "end_time": {"seconds": calendar.timegm(end_dt.timetuple()), "nanos": 0},
        })

        metrics_by_service = defaultdict(lambda: {"total_requests": 0, "error_5xx_requests": 0, "error_4xx_requests": 0, "p50_ms": None, "p95_ms": None, "project_id": "unknown"})

        # Process all metrics for this historical day
        for source in METRIC_SOURCES:
            count_agg = monitoring_v3.Aggregation(alignment_period={"seconds": 86400}, per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_DELTA, cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_SUM, group_by_fields=[f"resource.labels.{source['service_label']}", "metric.labels.response_code_class"])
            try:
                count_results = monitoring_client.list_time_series(request={"name": project_name, "filter": source["counts"], "interval": interval, "aggregation": count_agg})
                for result in count_results:
                    raw_name = result.resource.labels.get(source['service_label'])
                    if not raw_name or (source['prefix'] == 'endpoints' and raw_name.endswith('.googleapis.com')): continue
                    service_name = f"{source['prefix']}--{raw_name}"
                    if result.points:
                        val = result.points[0].value.int64_value
                        metrics_by_service[service_name]["total_requests"] += val
                        response_class = result.metric.labels.get("response_code_class", "2xx")
                        if str(response_class).startswith("5"):
                            metrics_by_service[service_name]["error_5xx_requests"] += val
                        elif str(response_class).startswith("4"):
                            metrics_by_service[service_name]["error_4xx_requests"] += val
                        pid = result.resource.labels.get("project_id")
                        if source['prefix'] == 'endpoints' and '.endpoints.' in raw_name:
                            try: pid = raw_name.split('.endpoints.')[1].split('.cloud.goog')[0]
                            except: pass
                        if pid: metrics_by_service[service_name]["project_id"] = pid
            except Exception as e:
                pass # Skip silently

            p50_agg = monitoring_v3.Aggregation(alignment_period={"seconds": 86400}, per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_PERCENTILE_50, cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_PERCENTILE_50, group_by_fields=[f"resource.labels.{source['service_label']}"])
            try:
                p50_results = monitoring_client.list_time_series(request={"name": project_name, "filter": source["latency"], "interval": interval, "aggregation": p50_agg})
                for result in p50_results:
                    raw_name = result.resource.labels.get(source['service_label'])
                    if not raw_name or (source['prefix'] == 'endpoints' and raw_name.endswith('.googleapis.com')): continue
                    service_name = f"{source['prefix']}--{raw_name}"
                    if result.points:
                        val = result.points[0].value.double_value
                        if source['prefix'] == 'endpoints': val *= 1000.0
                        metrics_by_service[service_name]["p50_ms"] = val
            except Exception:
                pass

            p95_agg = monitoring_v3.Aggregation(alignment_period={"seconds": 86400}, per_series_aligner=monitoring_v3.Aggregation.Aligner.ALIGN_PERCENTILE_95, cross_series_reducer=monitoring_v3.Aggregation.Reducer.REDUCE_PERCENTILE_95, group_by_fields=[f"resource.labels.{source['service_label']}"])
            try:
                p95_results = monitoring_client.list_time_series(request={"name": project_name, "filter": source["latency"], "interval": interval, "aggregation": p95_agg})
                for result in p95_results:
                    raw_name = result.resource.labels.get(source['service_label'])
                    if not raw_name or (source['prefix'] == 'endpoints' and raw_name.endswith('.googleapis.com')): continue
                    service_name = f"{source['prefix']}--{raw_name}"
                    if result.points:
                        val = result.points[0].value.double_value
                        if source['prefix'] == 'endpoints': val *= 1000.0
                        metrics_by_service[service_name]["p95_ms"] = val
            except Exception:
                pass

        # Push exactly this iteration's metrics to BQ
        metrics_data = []
        for service, agg in metrics_by_service.items():
            if agg["total_requests"] == 0:
                availability = 1.0
            else:
                availability = (agg["total_requests"] - agg["error_5xx_requests"]) / agg["total_requests"]
                
            metrics_data.append({
                "timestamp": datetime.utcnow().isoformat(),
                "target_date": target_date_str,
                "project_id": agg["project_id"],
                "service_name": service,
                "archetype": "sync",
                "availability_ratio": round(availability, 4),
                "total_requests": agg["total_requests"],
                "error_5xx_requests": agg["error_5xx_requests"],
                "error_4xx_requests": agg["error_4xx_requests"],
                "total_errors": agg["error_5xx_requests"] + agg["error_4xx_requests"],
                "latency_p50_ms": round(agg["p50_ms"], 2) if agg["p50_ms"] else None,
                "latency_p95_ms": round(agg["p95_ms"], 2) if agg["p95_ms"] else None
            })

        if metrics_data:
            table_id = f"{bq_client.project}.{BQ_DATASET}.{BQ_TABLE}"
            errors = bq_client.insert_rows_json(table_id, metrics_data)
            if errors:
                print(f"  -> Error inserting to BQ: {errors}")
            else:
                print(f"  -> Pushed {len(metrics_data)} rows.")
        else:
            print("  -> No traffic found.")

if __name__ == "__main__":
    # Query specific date range (1 day ago to 42 days ago)
    backfill(2, 42)
