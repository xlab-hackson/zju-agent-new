import { create } from "zustand";

interface FloatingChatState {
  isOpen: boolean;
  isMinimized: boolean;
  isExpanded: boolean;
  activeConversationId: string | null;
  position: { x: number; y: number } | null;
  prefillPrompt: string | null;
  openChat: (conversationId?: string, prompt?: string) => void;
  closeChat: () => void;
  toggleChat: () => void;
  minimizeChat: () => void;
  restoreChat: () => void;
  toggleExpand: () => void;
  setPosition: (pos: { x: number; y: number } | null) => void;
  setActiveConversationId: (id: string | null) => void;
  setPrefillPrompt: (prompt: string | null) => void;
}

export const useFloatingChatStore = create<FloatingChatState>((set) => ({
  isOpen: false,
  isMinimized: false,
  isExpanded: false,
  activeConversationId: null,
  position: null,
  prefillPrompt: null,
  openChat: (conversationId, prompt) =>
    set((state) => ({
      isOpen: true,
      isMinimized: false,
      activeConversationId:
        conversationId !== undefined ? conversationId : state.activeConversationId,
      prefillPrompt: prompt !== undefined ? prompt : state.prefillPrompt,
    })),
  closeChat: () => set({ isOpen: false }),
  toggleChat: () =>
    set((state) => ({
      isOpen: !state.isOpen || state.isMinimized,
      isMinimized: false,
    })),
  minimizeChat: () => set({ isMinimized: true }),
  restoreChat: () => set({ isMinimized: false, isOpen: true }),
  toggleExpand: () => set((state) => ({ isExpanded: !state.isExpanded })),
  setPosition: (position) => set({ position }),
  setActiveConversationId: (activeConversationId) => set({ activeConversationId }),
  setPrefillPrompt: (prefillPrompt) => set({ prefillPrompt }),
}));
