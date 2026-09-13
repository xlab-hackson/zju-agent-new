/** 校网充值领域类型 */

export type NetworkAccountStatus = {
  account: string;
  balance?: number;
  status?: string;
  packageName?: string;
  expiresAt?: string;
  raw?: unknown;
};

export type NetworkRechargeInput = {
  amount: number;
  account?: string;
  paymentMethod?: string;
};

export type NetworkRechargeResult = {
  orderId?: string;
  paymentUrl?: string;
  qrCodeUrl?: string;
  status: "pending_payment" | "completed" | "failed";
};
