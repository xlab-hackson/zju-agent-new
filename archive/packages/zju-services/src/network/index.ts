/**
 * 校网充值适配器。
 * 充值属于高风险操作，后端只负责生成/打开支付流程，不绕过用户确认。
 * 实际充值接口需探测，此处提供领域类型与占位实现。
 */

import {
  AppError,
  ErrorCode,
  type NetworkAccountStatus,
  type NetworkRechargeInput,
  type NetworkRechargeResult,
} from "@zju-agent/core";

export class NetworkService {
  /** 查询校网账号状态。实际接口需探测。 */
  async getAccountStatus(_account?: string): Promise<NetworkAccountStatus> {
    throw new AppError(
      ErrorCode.ZJU_SERVICE_UNAVAILABLE,
      "校网账户状态接口尚未实现。",
      { retryable: false },
    );
  }

  /**
   * 发起充值流程。返回 pending_payment 状态与支付二维码/链接。
   * 注意：本方法不完成支付，只生成支付入口，由前端展示确认。
   */
  async recharge(input: NetworkRechargeInput): Promise<NetworkRechargeResult> {
    if (!input.amount || input.amount <= 0) {
      throw new AppError(
        ErrorCode.TOOL_INPUT_INVALID,
        "充值金额无效。",
      );
    }
    throw new AppError(
      ErrorCode.NETWORK_RECHARGE_FAILED,
      "校网充值接口尚未实现。",
      { retryable: false },
    );
  }
}
