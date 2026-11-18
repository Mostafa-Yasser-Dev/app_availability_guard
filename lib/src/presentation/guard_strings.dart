/// Supply translated strings or custom builders from the host application.
class GuardStrings {
  const GuardStrings({
    this.maintenanceTitle = 'Scheduled maintenance',
    this.maintenanceMessage = 'Please try again shortly.',
    this.mandatoryTitle = 'Update required',
    this.optionalTitle = 'New update available',
    this.updateMessage = 'A newer application version is available.',
    this.updateNow = 'Update now',
    this.later = 'Later',
    this.retry = 'Check again',
    this.refreshError = 'Unable to check right now. Please try again.',
    this.storeError =
        'Unable to open the store. Please try again or update manually.',
  });
  final String maintenanceTitle,
      maintenanceMessage,
      mandatoryTitle,
      optionalTitle;
  final String updateMessage, updateNow, later, retry, refreshError, storeError;
}
