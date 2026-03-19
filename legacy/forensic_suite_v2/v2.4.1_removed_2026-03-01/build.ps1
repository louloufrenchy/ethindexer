task Install {
    pip install -e .
}

task Lint {
    flake8 forensic_suite_v2
}

task Test {
    pytest
}

task Health {
    python forensic_suite_v2/scripts/healthcheck.py
}

task Orchestrate {
    python forensic_suite_v2/scripts/orchestrator_service.py
}

task Console {
    python forensic_suite_v2/scripts/operator_console.py
}
