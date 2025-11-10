<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  opportunity: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['click']);

const { t } = useI18n();

const priorityColors = {
  low: 'bg-n-slate-9 text-n-slate-12',
  medium: 'bg-n-blue-9 text-n-blue-12',
  high: 'bg-n-orange-9 text-n-orange-12',
  urgent: 'bg-n-ruby-9 text-n-ruby-12',
};

const priorityLabel = computed(() => {
  return t(`OPPORTUNITIES.PRIORITY.${props.opportunity.priority?.toUpperCase()}`);
});

const priorityColor = computed(() => {
  return priorityColors[props.opportunity.priority] || priorityColors.medium;
});

const formattedValue = computed(() => {
  if (!props.opportunity.estimated_value) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(props.opportunity.estimated_value);
});

const contactName = computed(() => {
  return props.opportunity.contact?.name || props.opportunity.contact_name || '-';
});

const handleClick = () => {
  emit('click', props.opportunity);
};
</script>

<template>
  <div
    class="bg-n-background dark:bg-n-solid-1 border border-n-weak dark:border-n-weak/50 rounded-lg p-4 cursor-pointer hover:shadow-md transition-shadow"
    @click="handleClick"
  >
    <div class="flex flex-col gap-2">
      <div class="flex items-start justify-between gap-2">
        <h3 class="text-sm font-semibold text-n-slate-12 dark:text-n-slate-12 line-clamp-2 flex-1">
          {{ opportunity.title }}
        </h3>
        <span
          v-if="opportunity.priority"
          class="px-2 py-1 text-xs font-medium rounded whitespace-nowrap flex-shrink-0"
          :class="priorityColor"
        >
          {{ priorityLabel }}
        </span>
      </div>

      <div v-if="formattedValue" class="text-sm font-medium text-n-slate-11 dark:text-n-slate-11">
        {{ formattedValue }}
      </div>

      <div class="text-xs text-n-slate-10 dark:text-n-slate-10">
        {{ contactName }}
      </div>

      <div v-if="opportunity.opportunity_id" class="text-xs text-n-slate-9 dark:text-n-slate-9">
        {{ opportunity.opportunity_id }}
      </div>
    </div>
  </div>
</template>

