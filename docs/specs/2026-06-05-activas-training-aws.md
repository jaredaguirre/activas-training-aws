# Activas Training — AWS Infrastructure Spec

**Fecha:** 2026-06-05
**Proyecto:** activas-training-aws
**App repo:** `~/projects/activas-training` (Next.js 16.2.7, App Router)
**Marca:** Activas Training — Pamela Da Silva
**Objetivo:** Infraestructura AWS nativa para plataforma de cursos de entrenamiento para embarazadas

---

## 1. Contexto

La aplicación se divide en dos planes de entrega:

| Plan | Alcance | Estado |
|------|---------|--------|
| Plan A | Sitio público (home, landings de cursos) | Completo — pendiente deploy |
| Plan B | Auth + dashboard + video player | Pendiente |

La infraestructura en este repo soporta **ambos planes**. Algunos recursos (Cognito, DynamoDB) se activan en Plan B.

Audiencia objetivo: usuarias en Argentina (~300 MAU iniciales). Toda la infraestructura está orientada a latencia AR y cumplimiento de costos reducidos.

---

## 2. Servicios y roles

| Servicio | Rol | Costo estimado/mes |
|---------|-----|--------------------|
| AWS Amplify | Hosting SSR Next.js + CI/CD desde Git | ~$17.64 |
| S3 | Almacenamiento de videos y archivos de cursos | ~$0.12 |
| CloudFront | CDN + geo-restricción a AR + HTTPS | ~$11.50 |
| Amazon Cognito | Auth: registro, login, JWT, verificación de email | $0 (≤50K MAU) |
| DynamoDB | Base de datos de usuarios, inscripciones y progreso | $0 (free tier) |
| Route 53 | DNS manager para `mamisactivas.com.ar` | $0.50 |
| ACM | Certificado SSL wildcard `*.mamisactivas.com.ar` | $0 |
| **Total** | | **~$30–31/mes** |

---

## 3. Estructura Terraform

```
activas-training-aws/
  env/
    dev/
      main.tf        # todos los recursos del entorno dev
  docs/
    specs/
      2026-06-05-activas-training-aws.md
  .gitignore
  README.md
```

### Provider y backend

- **Provider:** `hashicorp/aws ~> 6.37` (mínimo para `bucket_namespace = "account-regional"`)
- **Backend:** S3 con bucket en regional namespace
  - Bucket: `terraform-state-700693144273-us-east-1-an`
  - Key: `terraform/state/activas-training/env/dev/terraform.tfstate`
  - Región: `us-east-1`
  - Profile: `jaguirre-aws-activas-training`

### Naming convention

Los buckets S3 siguen el **account regional namespace** de AWS (feature de marzo 2026):

```
{prefix}-{AWS_ACCOUNT_ID}-{region}-an
```

Ejemplo: `activas-training-media-700693144273-us-east-1-an`

Ventaja: el nombre queda reservado permanentemente a esta cuenta. Ninguna otra cuenta puede tomarlo.

---

## 4. Media: S3 + CloudFront

### Arquitectura

```
Usuaria (AR) → CloudFront (PriceClass_All, geo AR) → S3 media bucket (privado)
```

- El bucket S3 es **completamente privado** (todos los `block_public_*` activos).
- CloudFront accede vía **OAC (Origin Access Control)** con SigV4 signing.
- El bucket policy solo permite `s3:GetObject` al servicio `cloudfront.amazonaws.com` con condición `AWS:SourceArn` igual al ARN de la distribución.
- Geo-restricción: `whitelist = ["AR"]` — solicitudes de fuera de Argentina reciben 403.
- Cache: AWS managed **CachingOptimized** policy (`658327ea-f89d-4fab-a63d-7e88639e58f6`).
- Precio: `PriceClass_All` para incluir el edge de São Paulo (más cercano a AR).

### Viewer certificate

Por ahora: `cloudfront_default_certificate = true` (dominio `*.cloudfront.net`).
Cuando el dominio `mamisactivas.com.ar` esté registrado en nic.ar: reemplazar por ACM wildcard `*.mamisactivas.com.ar` (cert debe estar en `us-east-1`).

### Recursos definidos

| Recurso Terraform | Nombre en AWS |
|---|---|
| `aws_s3_bucket.media` | `activas-training-media-{accountId}-us-east-1-an` |
| `aws_s3_bucket_versioning.media` | — |
| `aws_s3_bucket_server_side_encryption_configuration.media` | AES256 + bucket key |
| `aws_s3_bucket_public_access_block.media` | todos bloqueados |
| `aws_cloudfront_origin_access_control.media` | `activas-training-media-oac` |
| `aws_cloudfront_distribution.media` | `activas-training-media-dev` |
| `aws_s3_bucket_policy.media` | OAC policy |

---

## 5. Auth — Amazon Cognito (Plan B)

### Flujo

```
App (Next.js) → Cognito User Pool → JWT → API Routes (Next.js)
               ↓
         Lambda trigger (post-confirmation) → DynamoDB Users
```

### User Pool

- Atributos: `email` (único), `name`
- Verificación de email habilitada
- Password policy: mínimo 8 caracteres, sin complejidad forzada (UX simple)
- Token: JWT con expiración configurable

### Lambda trigger

Post-confirmation trigger escribe el nuevo usuario en DynamoDB automáticamente:
```
userId (sub de Cognito) | name | plan | createdAt
```

### Recursos pendientes (Plan B)

- `aws_cognito_user_pool`
- `aws_cognito_user_pool_client`
- `aws_lambda_function` (post-confirmation trigger)
- `aws_iam_role` para la Lambda

---

## 6. Base de datos — DynamoDB (Plan B)

Diseño **single-table** con PK/SK compuestos desde el inicio.

### Tabla: `activas-training-{env}`

| Entidad | PK | SK | Atributos |
|---------|----|----|-----------|
| Usuario | `USER#{userId}` | `PROFILE` | name, email, plan, createdAt |
| Inscripción | `USER#{userId}` | `ENROLL#{courseId}` | enrolledAt |
| Progreso | `USER#{userId}` | `PROGRESS#{lessonId}` | completedAt, lastPosition |

Índices secundarios (GSI) a definir en Plan B según los patrones de acceso del dashboard.

---

## 7. Dominio y DNS

| Subdominio | Destino |
|-----------|---------|
| `mamisactivas.com.ar` | Amplify (sitio público) |
| `app.mamisactivas.com.ar` | Amplify (dashboard, Plan B) |
| `media.mamisactivas.com.ar` | CloudFront distribution |
| `api.mamisactivas.com.ar` | Next.js API routes vía Amplify |

### Pasos de setup de dominio

1. Registrar `mamisactivas.com.ar` en [nic.ar](https://nic.ar) (requiere CUIT/CUIL, ~ARS 800–1.500/año)
2. Crear hosted zone en Route 53 ($0.50/mes)
3. Apuntar nameservers de nic.ar a los NS de Route 53
4. Emitir certificado ACM wildcard `*.mamisactivas.com.ar` en `us-east-1` (validación DNS)
5. Reemplazar `cloudfront_default_certificate` por `acm_certificate_arn` en la distribución

> **Nota:** Route 53 no puede registrar `.com.ar` — el registro debe hacerse en nic.ar y luego delegar los NS a Route 53.

---

## 8. Amplify (Plan A deploy)

- Conectar repo `activas-training` desde GitHub/GitLab
- Branch `main` → entorno `dev`
- Next.js SSR: Amplify detecta automáticamente App Router
- Variables de entorno a configurar: ninguna para Plan A (todo estático/público)
- Costo: ~$17.64/mes basado en ~300 MAU

---

## 9. Decisiones técnicas relevantes

| Decisión | Alternativa descartada | Razón |
|----------|----------------------|-------|
| Cognito | Supabase Auth | Preferencia por stack nativo AWS |
| DynamoDB | RDS / Supabase Postgres | Free tier, no hay queries relacionales complejas |
| CloudFront geo-block | GCP Cloud Armor | Cloud Armor cobra extra (~$5/mes) vs CloudFront gratis |
| S3 regional namespace | Bucket global | Nombre reservado permanentemente, nunca tomado por otra cuenta |
| `PriceClass_All` | `PriceClass_100` | São Paulo edge para latencia óptima en AR |
| OAC (no OAI) | Origin Access Identity | OAI está deprecado, OAC es el estándar actual |

---

## 10. Outputs útiles

Después de `terraform apply`, los outputs disponibles son:

| Output | Uso |
|--------|-----|
| `media_bucket_name` | Nombre del bucket para uploads de videos |
| `media_bucket_arn` | ARN para políticas IAM |
| `cloudfront_distribution_id` | Para invalidaciones de caché |
| `cloudfront_distribution_arn` | Referencia desde otros recursos |
| `cloudfront_domain_name` | URL de la distribución (hasta configurar dominio custom) |
| `cloudfront_oac_id` | ID del OAC (referencia interna) |
