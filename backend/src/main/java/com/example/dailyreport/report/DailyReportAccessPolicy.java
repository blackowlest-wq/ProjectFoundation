/**
 * 日報の参照・操作に必要なロール判定とグループ権限制御を担当するComponent。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.ManagerGroupPermissionRepository;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.report.entity.DailyReportEntity;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class DailyReportAccessPolicy {
    private final ManagerGroupPermissionRepository managerGroupPermissionRepository;

    public DailyReportAccessPolicy(ManagerGroupPermissionRepository managerGroupPermissionRepository) {
        this.managerGroupPermissionRepository = managerGroupPermissionRepository;
    }

    /**
     * 登録・更新・提出を実行できる社員であることを確認し、業務処理用の利用者を返す。
     */
    public AppUser requireEmployee(AuthenticatedUser principal) {
        // Why not: リクエストの社員IDを信頼すると他者の日報を操作できるため、登録・編集・提出は本人だけに限定する。
        // How: 社員以外は業務処理へ進めず、権限エラーを即時に返す。
        if (principal.user().getRole() != Role.EMPLOYEE) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only employees can use this operation.");
        }
        return principal.user();
    }

    /**
     * 利用者ロールに応じて、指定日報の参照可否を判定する。
     * 社員は本人、上長は許可グループ、管理者は全件を参照できる。
     */
    public boolean canReadReport(AppUser user, DailyReportEntity report) {
        // How: 社員は自分の利用者IDと日報の社員IDが一致する場合だけ参照を許可する。
        if (user.getRole() == Role.EMPLOYEE) {
            return report.getEmployeeUserId().equals(user.getUserId());
        }
        // How: 上長は許可グループに属する日報だけ参照を許可する。
        if (user.getRole() == Role.MANAGER) {
            return managerGroupPermissionRepository.permittedGroupIds(user.getUserId()).contains(report.getGroupId());
        }
        // How: 社員・上長以外は管理者だけを全件参照可能とし、その他のロールは拒否する。
        return user.getRole() == Role.ADMIN;
    }

    /**
     * 検索条件として指定されたグループを、上長の許可範囲へ絞り込んで返す。
     */
    public List<String> permittedGroupIds(AppUser user, String requestedGroupId) {
        // How: 上長以外にはグループ検索条件を返さず、検索時の権限絞り込みを適用しない。
        if (user.getRole() != Role.MANAGER) {
            return List.of();
        }
        List<String> permitted = managerGroupPermissionRepository.permittedGroupIds(user.getUserId());
        // How: グループ未指定なら上長の全許可グループを返し、指定時はその1件だけを許可範囲と照合する。
        if (requestedGroupId == null || requestedGroupId.isBlank()) {
            return permitted;
        }
        return permitted.contains(requestedGroupId) ? List.of(requestedGroupId) : List.of();
    }
}
