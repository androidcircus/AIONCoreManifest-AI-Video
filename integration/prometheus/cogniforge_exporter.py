from prometheus_client import start_http_server, Gauge, Histogram
import random, time

warp_occupancy = Gauge('cogniforge_warp_occupancy', 'Warp occupancy ratio', ['sm_id'])
tensor_tflops = Gauge('cogniforge_tensor_tflops', 'Tensor TFLOPS', ['sm_id'])
rdma_atomic_latency_us = Histogram('cogniforge_rdma_atomic_latency_us', 'RDMA atomic latency')

def collect_metrics():
    for sm_id in range(25600):
        warp_occupancy.labels(sm_id=str(sm_id)).set(random.random())
        tensor_tflops.labels(sm_id=str(sm_id)).set(random.uniform(0.1, 0.5))

if __name__ == '__main__':
    start_http_server(9400)
    while True:
        collect_metrics()
        time.sleep(1)
