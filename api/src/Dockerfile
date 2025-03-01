FROM node:18-alpine

WORKDIR /health-check-api

COPY package*.json ./

RUN npm install --force

COPY . .


CMD ["node", "server.js"]