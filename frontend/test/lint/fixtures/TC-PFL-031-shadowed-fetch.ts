function useLocal(fetch: () => void) {
  fetch();
}

useLocal(() => undefined);
