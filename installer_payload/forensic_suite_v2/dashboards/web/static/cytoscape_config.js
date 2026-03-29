// forensic_suite_v2/dashboards/web/static/cytoscape_config.js

let globalCy;

function initGraph(elements) {
    // Add risk scores to nodes
    elements.forEach(ele => {
        if (ele.data && !ele.data.source) {
            ele.data.risk_score = calculateRisk(ele.data);
        }
    });

    globalCy = cytoscape({
        container: document.getElementById('cy'),
        elements: elements,
        style: [
            {
                selector: 'node',
                style: {
                    'label': 'data(label)',
                    'color': '#fff',
                    'font-size': '10px',
                    'background-color': '#67b3ff',
                    'text-valign': 'bottom',
                    'text-margin-y': '5px'
                }
            },
            // Auto-Trace Pulse Effect
            {
                selector: 'node[risk_score >= 80]',
                style: {
                    'border-width': '4px',
                    'border-color': '#f31260',
                    'overlay-color': '#f31260',
                    'overlay-opacity': 0.3,
                    'width': '50px',
                    'height': '50px'
                }
            },
            // Standard Chain Colors
            { selector: 'node[chain="btc"]', style: { 'background-color': '#f7931a' } },
            { selector: 'node[chain="eth"]', style: { 'background-color': '#627eea' } },
            { selector: 'node[chain="tron"]', style: { 'background-color': '#ef0027' } },
            {
                selector: 'edge',
                style: {
                    'width': '2px',
                    'line-color': '#283355',
                    'target-arrow-shape': 'triangle',
                    'curve-style': 'bezier'
                }
            }
        ],
        layout: { name: 'cose', animate: true }
    });

    globalCy.on('tap', 'node', function(evt){
        const d = evt.target.data();
        document.getElementById('info').innerHTML = `<b>Address:</b> ${d.label}<br><b>Risk:</b> ${d.risk_score}%`;
    });
}

function calculateRisk(data) {
    let score = 10;
    if (data.multi_chain) score += 30;
    if (data.pattern === "PEEL_CHAIN") score += 50;
    if (data.pattern === "CIRCULAR_FLOW") score += 70;
    return Math.min(score, 100);
}

function downloadGraph() {
    const png = globalCy.png({ full: true, bg: '#09101f' });
    const link = document.createElement('a');
    link.href = png;
    link.download = `Forensic_Trace_${Date.now()}.png`;
    link.click();
}
