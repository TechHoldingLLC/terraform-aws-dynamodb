# terraform-aws-dynamodb — Examples

This document provides detailed, copy-pasteable examples for the `terraform-aws-dynamodb` module. Each example is self-contained and highlights a specific feature set.

- [1. Minimal table (on-demand)](#1-minimal-table-on-demand)
- [2. Table with a composite key (hash + range)](#2-table-with-a-composite-key-hash--range)
- [3. Provisioned capacity](#3-provisioned-capacity)
- [4. TTL and point-in-time recovery](#4-ttl-and-point-in-time-recovery)
- [5. Streams enabled](#5-streams-enabled)
- [6. Global secondary indexes (GSI)](#6-global-secondary-indexes-gsi)
- [7. Local secondary indexes (LSI)](#7-local-secondary-indexes-lsi)
- [8. Everything together (production-style)](#8-everything-together-production-style)
- [Referencing the module outputs](#referencing-the-module-outputs)

> **Note on `attributes`**
> DynamoDB only requires attribute definitions for keys — that is, the `hash_key`, the `range_key`, and any attributes used as keys in a GSI or LSI. Do **not** list non-key attributes here; DynamoDB is schemaless for everything else. Each entry needs a `name` and a `type` of `S` (String), `N` (Number), or `B` (Binary).

---

## 1. Minimal table (on-demand)

The simplest possible table: a single partition key, billed per-request (the module default).

```hcl
module "users" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "users"
  hash_key   = "user_id"

  attributes = [
    {
      name = "user_id"
      type = "S"
    }
  ]
}
```

---

## 2. Table with a composite key (hash + range)

Use a `range_key` (sort key) to model one-to-many relationships within a partition.

```hcl
module "orders" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "orders"
  hash_key   = "customer_id"
  range_key  = "order_id"

  attributes = [
    {
      name = "customer_id"
      type = "S"
    },
    {
      name = "order_id"
      type = "S"
    }
  ]
}
```

---

## 3. Provisioned capacity

Switch to `PROVISIONED` billing when you have predictable traffic and want to control cost. When `billing_mode = "PROVISIONED"`, both `read_capacity` and `write_capacity` are required and must be greater than 0.

```hcl
module "sessions" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name     = "sessions"
  billing_mode   = "PROVISIONED"
  read_capacity  = 25
  write_capacity = 25

  hash_key = "session_id"

  attributes = [
    {
      name = "session_id"
      type = "S"
    }
  ]
}
```

---

## 4. TTL and point-in-time recovery

Automatically expire items with a TTL attribute (a Unix epoch timestamp, in seconds), and protect against accidental data loss with point-in-time recovery (PITR).

```hcl
module "events" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "events"
  hash_key   = "event_id"

  attributes = [
    {
      name = "event_id"
      type = "S"
    }
  ]

  # Expire items whose `expires_at` epoch timestamp is in the past.
  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  # Enable continuous backups; retain restore points for 14 days.
  point_in_time_recovery_enabled = true
  recovery_period_in_days        = 14

  # Prevent `terraform destroy` from deleting the table.
  deletion_protection_enabled = true
}
```

---

## 5. Streams enabled

Emit a change stream that can trigger a Lambda, replicate data, or feed downstream systems. `stream_view_type` controls what each stream record contains.

```hcl
module "audit_log" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "audit_log"
  hash_key   = "record_id"

  attributes = [
    {
      name = "record_id"
      type = "S"
    }
  ]

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES" # KEYS_ONLY | NEW_IMAGE | OLD_IMAGE | NEW_AND_OLD_IMAGES
}
```

The stream ARN is exported as an output — wire it into a Lambda event source mapping:

```hcl
resource "aws_lambda_event_source_mapping" "audit_processor" {
  event_source_arn  = module.audit_log.stream_arn
  function_name     = aws_lambda_function.processor.arn
  starting_position = "LATEST"
}
```

---

## 6. Global secondary indexes (GSI)

GSIs let you query on alternate keys. Every attribute referenced by a GSI key must also appear in the top-level `attributes` list.

```hcl
module "users" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "users"
  hash_key   = "user_id"

  attributes = [
    {
      name = "user_id"
      type = "S"
    },
    {
      name = "email"
      type = "S"
    },
    {
      name = "status"
      type = "S"
    },
    {
      name = "created_at"
      type = "N"
    }
  ]

  global_secondary_indexes = [
    # Query users by email (hash-only GSI, project all attributes).
    {
      name            = "email-index"
      projection_type = "ALL"

      key_schema = [
        {
          attribute_name = "email"
          key_type       = "HASH"
        }
      ]
    },
    # Query users by status, sorted by creation time. Project a subset of attributes.
    {
      name               = "status-created-index"
      projection_type    = "INCLUDE"
      non_key_attributes = ["email"]

      key_schema = [
        {
          attribute_name = "status"
          key_type       = "HASH"
        },
        {
          attribute_name = "created_at"
          key_type       = "RANGE"
        }
      ]
    }
  ]
}
```

### GSI with per-index provisioned capacity

When the table uses `PROVISIONED` billing, set `read_capacity` / `write_capacity` on each GSI:

```hcl
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20

  global_secondary_indexes = [
    {
      name            = "email-index"
      projection_type = "ALL"
      read_capacity   = 10
      write_capacity  = 10

      key_schema = [
        {
          attribute_name = "email"
          key_type       = "HASH"
        }
      ]
    }
  ]
```

### GSI with on-demand throughput caps

When the table uses `PAY_PER_REQUEST` billing, you can optionally cap a GSI's maximum throughput:

```hcl
  global_secondary_indexes = [
    {
      name            = "email-index"
      projection_type = "ALL"

      key_schema = [
        {
          attribute_name = "email"
          key_type       = "HASH"
        }
      ]

      on_demand_throughput = {
        max_read_request_units  = 1000
        max_write_request_units = 500
      }
    }
  ]
```

---

## 7. Local secondary indexes (LSI)

LSIs share the table's partition key but use an alternate sort key. They **must** be defined at table creation and cannot be changed afterward. The table therefore requires a `range_key`.

```hcl
module "orders" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name = "orders"
  hash_key   = "customer_id"
  range_key  = "order_id"

  attributes = [
    {
      name = "customer_id"
      type = "S"
    },
    {
      name = "order_id"
      type = "S"
    },
    {
      name = "order_date"
      type = "N"
    }
  ]

  local_secondary_indexes = [
    {
      name            = "orders-by-date-index"
      range_key       = "order_date"
      projection_type = "ALL"
    }
  ]
}
```

---

## 8. Everything together (production-style)

A composite-key table combining provisioned capacity, TTL, PITR, streams, deletion protection, a GSI, an LSI, and the Standard-Infrequent-Access storage class.

```hcl
module "orders" {
  source = "git::https://github.com/TechHoldingLLC/terraform-aws-dynamodb.git?ref=v1.0.0"

  table_name  = "orders-prod"
  table_class = "STANDARD_INFREQUENT_ACCESS"

  hash_key  = "customer_id"
  range_key = "order_id"

  billing_mode   = "PROVISIONED"
  read_capacity  = 50
  write_capacity = 50

  attributes = [
    { name = "customer_id", type = "S" },
    { name = "order_id", type = "S" },
    { name = "order_date", type = "N" },
    { name = "status", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "status-index"
      projection_type = "ALL"
      read_capacity   = 20
      write_capacity  = 20

      key_schema = [
        { attribute_name = "status", key_type = "HASH" },
        { attribute_name = "order_date", key_type = "RANGE" }
      ]
    }
  ]

  local_secondary_indexes = [
    {
      name            = "orders-by-date-index"
      range_key       = "order_date"
      projection_type = "KEYS_ONLY"
    }
  ]

  ttl_enabled        = true
  ttl_attribute_name = "expires_at"

  point_in_time_recovery_enabled = true
  recovery_period_in_days        = 35

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  deletion_protection_enabled = true
}
```

---

## Referencing the module outputs

The module exposes the table identifiers and stream metadata:

```hcl
output "orders_table_arn" {
  value = module.orders.arn
}

output "orders_table_name" {
  value = module.orders.id
}

# Only populated when stream_enabled = true, otherwise null.
output "orders_stream_arn" {
  value = module.orders.stream_arn
}

output "orders_stream_label" {
  value = module.orders.stream_label
}
```

| Output | Description |
|--------|-------------|
| `arn` | ARN of the DynamoDB table |
| `id` | Name/ID of the DynamoDB table |
| `stream_arn` | ARN of the table stream (only when `stream_enabled = true`, else `null`) |
| `stream_label` | ISO 8601 timestamp of the stream (only when `stream_enabled = true`, else `null`) |
