/* global axios */
import ApiClient from './ApiClient';

class OpportunitiesAPI extends ApiClient {
  constructor() {
    super('opportunities', { accountScoped: true });
  }

  get({ page = 1, searchKey, filters } = {}) {
    return axios.get(this.url, {
      params: { page, searchKey, ...filters },
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data = {}) {
    return axios.post(this.url, {
      opportunity: data,
    });
  }

  update(id, data = {}) {
    return axios.patch(`${this.url}/${id}`, {
      opportunity: data,
    });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  kanban(filters = {}) {
    return axios.get(`${this.url}/kanban`, {
      params: filters,
    });
  }

  moveStage(id, stage) {
    return axios.patch(`${this.url}/${id}/move_stage`, {
      stage,
    });
  }

  markWon(id) {
    return axios.post(`${this.url}/${id}/mark_won`);
  }

  markLost(id, reason) {
    return axios.post(`${this.url}/${id}/mark_lost`, {
      reason,
    });
  }
}

export default new OpportunitiesAPI();

