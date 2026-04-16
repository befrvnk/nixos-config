export function shouldRegisterBashTool(
  registeredCwd: string | undefined,
  nextCwd: string,
): boolean {
  return registeredCwd !== nextCwd;
}
