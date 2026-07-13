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

    public AppUser requireEmployee(AuthenticatedUser principal) {
        // Why not: リクエストの社員IDを信頼すると他者の日報を操作できるため、登録・編集・提出は本人だけに限定する。
        if (principal.user().getRole() != Role.EMPLOYEE) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only employees can use this operation.");
        }
        return principal.user();
    }

    public boolean canReadReport(AppUser user, DailyReportEntity report) {
        if (user.getRole() == Role.EMPLOYEE) {
            return report.getEmployeeUserId().equals(user.getUserId());
        }
        if (user.getRole() == Role.MANAGER) {
            return managerGroupPermissionRepository.permittedGroupIds(user.getUserId()).contains(report.getGroupId());
        }
        return user.getRole() == Role.ADMIN;
    }

    public List<String> permittedGroupIds(AppUser user, String requestedGroupId) {
        if (user.getRole() != Role.MANAGER) {
            return List.of();
        }
        List<String> permitted = managerGroupPermissionRepository.permittedGroupIds(user.getUserId());
        if (requestedGroupId == null || requestedGroupId.isBlank()) {
            return permitted;
        }
        return permitted.contains(requestedGroupId) ? List.of(requestedGroupId) : List.of();
    }
}
