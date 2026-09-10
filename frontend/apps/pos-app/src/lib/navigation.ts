const AUTH_ONLY_PATHS = ['/login', '/verify-email']

export function getSafeRedirectPath(value: string | null): string {
  const path = value?.trim() || '/'

  if (
    !path.startsWith('/') ||
    path.startsWith('//') ||
    AUTH_ONLY_PATHS.some((authPath) => path === authPath || path.startsWith(`${authPath}?`))
  ) {
    return '/'
  }

  return path
}