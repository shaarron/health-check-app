FROM node:18-alpine

WORKDIR /health-check-frontend

COPY package*.json ./

RUN npm install --force

COPY . .

CMD ["npm", "run", "dev"]