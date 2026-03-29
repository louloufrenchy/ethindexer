const summaryEl = document.getElementById("summary-text");
const blocksCtx = document.getElementById("blocksChart").getContext("2d");
const txCtx = document.getElementById("txChart").getContext("2d");

let blocksChart = new Chart(blocksCtx, {
  type: "bar",
  data: {
    labels: ["ETH", "BTC", "TRON"],
    datasets: [
      {
        label: "Last Block",
        data: [0, 0, 0],
        backgroundColor: ["#4caf50", "#2196f3", "#ff9800"],
      },
    ],
  },
  options: { responsive: true, scales: { y: { beginAtZero: true } } },
});

let txChart = new Chart(txCtx, {
  type: "bar",
  data: {
    labels: ["ETH", "BTC", "TRON"],
    datasets: [
      {
        label: "Total Transactions",
        data: [0, 0, 0],
        backgroundColor: ["#4caf50", "#2196f3", "#ff9800"],
      },
    ],
  },
  options: { responsive: true, scales: { y: { beginAtZero: true } } },
});

async function fetchJSON(url) {
  const res = await fetch(url);
  return await res.json();
}

async function refresh() {
  try {
    const [summary, tx] = await Promise.all([
      fetchJSON("/metrics/summary"),
      fetchJSON("/metrics/transactions"),
    ]);

    const cps = summary.checkpoints;
    const counts = tx.counts;

    let text = `Last refresh: ${summary.ts}\n\n`;
    for (const cp of cps) {
      const chain = cp.chain;
      text += `${chain.toUpperCase()}: last_block=${cp.last_block}, updated_at=${cp.updated_at}, tx_count=${counts[chain]}\n`;
    }
    summaryEl.textContent = text;

    const lastBlocks = {
      eth: 0,
      btc: 0,
      tron: 0,
    };
    cps.forEach((cp) => {
      lastBlocks[cp.chain] = cp.last_block;
    });

    blocksChart.data.datasets[0].data = [
      lastBlocks.eth,
      lastBlocks.btc,
      lastBlocks.tron,
    ];
    blocksChart.update();

    txChart.data.datasets[0].data = [
      counts.eth ?? 0,
      counts.btc ?? 0,
      counts.tron ?? 0,
    ];
    txChart.update();
  } catch (e) {
    summaryEl.textContent = `ERROR: ${e}`;
  }
}

setInterval(refresh, 5000);
refresh();
