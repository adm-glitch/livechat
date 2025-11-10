<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Draggable from 'vuedraggable';
import OpportunityCard from './OpportunityCard.vue';
import OpportunitiesAPI from 'dashboard/api/opportunities';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const STAGES = [
  { key: 'new_lead', value: 0 },
  { key: 'qualification', value: 1 },
  { key: 'scheduling_pending', value: 2 },
  { key: 'appointment_scheduled', value: 3 },
  { key: 'appointment_confirmed', value: 4 },
  { key: 'completed', value: 5 },
  { key: 'follow_up', value: 6 },
];

const props = defineProps({
  onCreateClick: {
    type: Function,
    default: null,
  },
});

const emit = defineEmits(['cardClick']);

const { t } = useI18n();
const { accountId } = useAccount();

const isLoading = ref(false);
const stagesData = ref({});
const opportunitiesByStage = ref({});

// Filters
const assignedAgentId = ref(null);
const priority = ref(null);
const dateRange = ref({ start: null, end: null });

const filters = computed(() => {
  const filterParams = {};
  if (assignedAgentId.value) {
    filterParams.assigned_agent_id = assignedAgentId.value;
  }
  if (priority.value) {
    filterParams.priority = priority.value;
  }
  if (dateRange.value.start) {
    filterParams.start_date = dateRange.value.start;
  }
  if (dateRange.value.end) {
    filterParams.end_date = dateRange.value.end;
  }
  return filterParams;
});

const initializeStages = () => {
  STAGES.forEach(stage => {
    opportunitiesByStage.value[stage.key] = [];
  });
};

const fetchKanbanData = async () => {
  isLoading.value = true;
  try {
    const response = await OpportunitiesAPI.kanban(filters.value);
    const { stages, totals } = response.data;

    // Initialize stages data
    stagesData.value = {};
    opportunitiesByStage.value = {};

    STAGES.forEach(stage => {
      const stageData = stages.find(s => s.stage === stage.key) || {
        stage: stage.key,
        count: 0,
        total_value: 0,
        opportunities: [],
      };
      stagesData.value[stage.key] = stageData;
      opportunitiesByStage.value[stage.key] = stageData.opportunities || [];
    });
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      t('OPPORTUNITIES.KANBAN.ERROR_FETCH');
    useAlert(errorMessage);
  } finally {
    isLoading.value = false;
  }
};

const previousStageMap = ref({});

const handleStageChange = async (event, stageKey) => {
  const { item, to } = event;
  const opportunityId = Number(item.dataset?.id || item.getAttribute('data-id'));
  
  if (!opportunityId) return;

  // Find opportunity in current stage
  const opportunity = opportunitiesByStage.value[stageKey]?.find(opp => opp.id === opportunityId);
  if (!opportunity) return;

  const oldStage = previousStageMap.value[opportunityId] || Object.keys(opportunitiesByStage.value).find(key =>
    key !== stageKey && opportunitiesByStage.value[key]?.some(opp => opp.id === opportunityId)
  );

  // If moved to different stage, update backend
  if (oldStage && oldStage !== stageKey) {
    try {
      await OpportunitiesAPI.moveStage(opportunityId, stageKey);
      useAlert(t('OPPORTUNITIES.KANBAN.STAGE_UPDATED'));
      // Remove from old stage
      if (opportunitiesByStage.value[oldStage]) {
        opportunitiesByStage.value[oldStage] = opportunitiesByStage.value[oldStage].filter(
          opp => opp.id !== opportunityId
        );
      }
    } catch (error) {
      // Revert: move back to old stage
      if (oldStage && opportunitiesByStage.value[oldStage]) {
        opportunitiesByStage.value[oldStage].push(opportunity);
      }
      opportunitiesByStage.value[stageKey] = opportunitiesByStage.value[stageKey].filter(
        opp => opp.id !== opportunityId
      );

      const errorMessage =
        error?.response?.data?.error ||
        error?.response?.data?.message ||
        t('OPPORTUNITIES.KANBAN.ERROR_UPDATE');
      useAlert(errorMessage);
    }
  }

  // Update previous stage map
  previousStageMap.value[opportunityId] = stageKey;
};

const handleCardClick = opportunity => {
  emit('cardClick', opportunity);
};

const handleCreateClick = () => {
  if (props.onCreateClick) {
    props.onCreateClick();
  }
};

const stageTitle = stageKey => {
  return t(`OPPORTUNITIES.STAGES.${stageKey.toUpperCase()}`);
};

watch(filters, () => {
  fetchKanbanData();
}, { deep: true });

onMounted(() => {
  initializeStages();
  fetchKanbanData();
});
</script>

<template>
  <div class="opportunity-kanban h-full flex flex-col">
    <!-- Filters Bar -->
    <div class="bg-n-background dark:bg-n-solid-1 border-b border-n-weak dark:border-n-weak/50 p-4 flex items-center gap-4 flex-wrap">
      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-11 dark:text-n-slate-11">
          {{ t('OPPORTUNITIES.KANBAN.FILTERS.AGENT') }}
        </label>
        <input
          v-model.number="assignedAgentId"
          type="number"
          :placeholder="t('OPPORTUNITIES.KANBAN.FILTERS.AGENT_PLACEHOLDER')"
          class="px-3 py-1.5 text-sm border border-n-weak dark:border-n-weak/50 rounded bg-n-background dark:bg-n-solid-1 text-n-slate-12 dark:text-n-slate-12"
        />
      </div>

      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-11 dark:text-n-slate-11">
          {{ t('OPPORTUNITIES.KANBAN.FILTERS.PRIORITY') }}
        </label>
        <select
          v-model="priority"
          class="px-3 py-1.5 text-sm border border-n-weak dark:border-n-weak/50 rounded bg-n-background dark:bg-n-solid-1 text-n-slate-12 dark:text-n-slate-12"
        >
          <option value="">{{ t('OPPORTUNITIES.KANBAN.FILTERS.ALL') }}</option>
          <option value="low">{{ t('OPPORTUNITIES.PRIORITY.LOW') }}</option>
          <option value="medium">{{ t('OPPORTUNITIES.PRIORITY.MEDIUM') }}</option>
          <option value="high">{{ t('OPPORTUNITIES.PRIORITY.HIGH') }}</option>
          <option value="urgent">{{ t('OPPORTUNITIES.PRIORITY.URGENT') }}</option>
        </select>
      </div>

      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-11 dark:text-n-slate-11">
          {{ t('OPPORTUNITIES.KANBAN.FILTERS.DATE_START') }}
        </label>
        <input
          v-model="dateRange.start"
          type="date"
          class="px-3 py-1.5 text-sm border border-n-weak dark:border-n-weak/50 rounded bg-n-background dark:bg-n-solid-1 text-n-slate-12 dark:text-n-slate-12"
        />
      </div>

      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-11 dark:text-n-slate-11">
          {{ t('OPPORTUNITIES.KANBAN.FILTERS.DATE_END') }}
        </label>
        <input
          v-model="dateRange.end"
          type="date"
          class="px-3 py-1.5 text-sm border border-n-weak dark:border-n-weak/50 rounded bg-n-background dark:bg-n-solid-1 text-n-slate-12 dark:text-n-slate-12"
        />
      </div>

      <div class="ml-auto">
        <Button
          variant="solid"
          color-scheme="primary"
          size="sm"
          @click="handleCreateClick"
        >
          <span class="mr-1">+</span>
          {{ t('OPPORTUNITIES.KANBAN.CREATE_BUTTON') }}
        </Button>
      </div>
    </div>

    <!-- Kanban Board -->
    <div v-if="isLoading" class="flex-1 flex items-center justify-center">
      <Spinner />
    </div>

    <div
      v-else
      class="flex-1 overflow-x-auto overflow-y-hidden p-4"
    >
      <div class="flex gap-4 h-full min-w-max">
        <div
          v-for="stage in STAGES"
          :key="stage.key"
          class="flex-shrink-0 w-80 flex flex-col bg-n-slate-2 dark:bg-n-solid-2 rounded-lg border border-n-weak dark:border-n-weak/50"
        >
          <!-- Stage Header -->
          <div class="p-4 border-b border-n-weak dark:border-n-weak/50">
            <h3 class="text-sm font-semibold text-n-slate-12 dark:text-n-slate-12">
              {{ stageTitle(stage.key) }}
            </h3>
            <p class="text-xs text-n-slate-10 dark:text-n-slate-10 mt-1">
              {{ stagesData[stage.key]?.count || 0 }} {{ t('OPPORTUNITIES.KANBAN.CARDS') }}
            </p>
          </div>

          <!-- Stage Cards -->
          <div class="flex-1 overflow-y-auto p-4 space-y-3">
            <Draggable
              v-model="opportunitiesByStage[stage.key]"
              :group="'opportunities'"
              item-key="id"
              :animation="200"
              ghost-class="opacity-50"
              class="space-y-3"
              @start="event => { const id = event.item?.dataset?.id || event.item?.getAttribute?.('data-id'); if (id) previousStageMap.value[id] = stage.key; }"
              @end="event => handleStageChange(event, stage.key)"
            >
              <template #item="{ element }">
                <div :data-id="element.id">
                  <OpportunityCard
                    :opportunity="element"
                    @click="handleCardClick"
                  />
                </div>
              </template>
            </Draggable>

            <div
              v-if="!opportunitiesByStage[stage.key]?.length"
              class="text-center py-8 text-sm text-n-slate-9 dark:text-n-slate-9"
            >
              {{ t('OPPORTUNITIES.KANBAN.EMPTY_STAGE') }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.opportunity-kanban {
  min-height: 0;
}
</style>

