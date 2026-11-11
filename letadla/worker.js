// Cloudflare Worker izomapa-letadla: obslouží api/flights pro mapu na statickém hostingu (R2).
// Kód prostředníka se nekopíruje, jen se importuje beze změny z functions/api/flights.js.
import { onRequest } from '../functions/api/flights.js';

export default {
  async fetch(request) {
    return onRequest({ request });
  },
};
