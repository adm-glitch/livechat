<script setup>
import { ref } from 'vue';
import OpportunityKanban from 'dashboard/components/crm/OpportunityKanban.vue';

const selectedOpportunity = ref(null);
const showOpportunityModal = ref(false);

const handleCardClick = opportunity => {
  selectedOpportunity.value = opportunity;
  showOpportunityModal.value = true;
  // TODO: Implementar modal de detalhes
};

const handleCreateClick = () => {
  // TODO: Implementar modal de criação
  console.log('Create opportunity clicked');
};
</script>

<template>
  <div class="h-full flex flex-col">
    <div class="flex-1 min-h-0">
      <OpportunityKanban
        @card-click="handleCardClick"
        @create-click="handleCreateClick"
      />
    </div>
  </div>
</template>

