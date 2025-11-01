FROM node:20-alpine as builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
# build backend
RUN npm run build
# build admin
COPY admin/package.json admin/package.json
COPY admin/package-lock.json* admin/
RUN cd admin && npm install --no-audit --no-fund
COPY admin admin
RUN cd admin && npm run build

FROM node:20-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/admin/dist ./admin/dist
EXPOSE 8080
CMD ["node", "dist/index.js"]


