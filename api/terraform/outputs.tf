output "load_balancer_url" {
  value = aws_lb.ecs_lb.dns_name
}

output "task_name" {
  description = "extract task name"
  value       = element(split(":", element(split("/", aws_ecs_service.service.task_definition), 1)), 0)
}

output "service_name" {
  value = aws_ecs_service.service.name
}

output "cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}

output "container_name" {
  value = jsondecode(aws_ecs_task_definition.api-health-check-task-definition.container_definitions)[0].name
}


