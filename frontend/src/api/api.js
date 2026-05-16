import axios from 'axios'

const base = import.meta.env.VITE_API_BASE || '/api'

const api = axios.create({
  baseURL: base,
  timeout: 10000,
})

export default api
