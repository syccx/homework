import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { FormService } from '../common/FormService';

/**
 * 新增及系统刷新都从磁盘回填，不依赖主应用是否已经启动。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(FormService.readSaved(this.context));
  }

  onUpdateForm(formId: string): void {
    FormService.updateFromDisk(this.context, formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    Object.keys(newStatus).forEach((formId: string) => {
      if (newStatus[formId] === formInfo.VisibilityType.FORM_VISIBLE) {
        FormService.updateFromDisk(this.context, formId);
      }
    });
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
