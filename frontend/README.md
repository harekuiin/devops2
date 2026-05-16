# Frontend

Instrucciones básicas:

- Recomendado: usar `pnpm` para instalar dependencias (se generó `pnpm-lock.yaml`).

- Instalar Corepack (opcional, permite usar `pnpm` sin instalar globalmente):

```bash
corepack enable
```

- Instalar dependencias:

```bash
pnpm install
```

- Desarrollo:

```bash
pnpm run dev
```

- Construir:

```bash
pnpm run build
```

- Construir imagen Docker (desde la raíz `frontend`):

```bash
docker build -t frontend:latest .
```

Notas:
- No comitees archivos `.env` con valores sensibles. Usa `frontend/.env.example` como plantilla y coloca secretos en GitHub Secrets o en tu proveedor de secretos.

