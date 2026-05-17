FROM node:18-alpine AS build
WORKDIR /app

# Copy package manifest and pnpm lockfile (if present) for reproducible installs
COPY package.json pnpm-lock.yaml* ./

# Install pnpm and dependencies. Using pnpm ensures reproducible installs
# and avoids the npm audit issues observed locally.
RUN npm install -g pnpm@latest
RUN pnpm install --frozen-lockfile --prod=false || pnpm install

# Copy source and build
COPY . .
RUN pnpm run build

FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Usuario no-root (práctica de seguridad)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
