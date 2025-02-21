# Zonal WarpStream ECS

Configuration in this directory deploys a WarpStream cluster within ECS.

This zonal deployment deploys a single ECS cluster with a single ECS service in a single zone.

This setup allows either a reduced availability in a zone outage or the ability to have independent
ECS clusters and services per zone allowing more control over upgrades.

This example deploys three instances of the module one in each zone.
