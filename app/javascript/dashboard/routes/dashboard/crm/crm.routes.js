import { frontendURL } from '../../../helper/URLHelper';
import CRMIndex from './Index.vue';

const commonMeta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    component: CRMIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'crm_dashboard_index',
        component: CRMIndex,
        meta: commonMeta,
      },
    ],
  },
];

