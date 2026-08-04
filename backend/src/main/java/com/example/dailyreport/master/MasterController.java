/**
 * 日報画面のプルダウンに使うマスタAPIを提供するController。
 * 案件、作業分類、休日区分をログイン済みユーザーへ返す。
 */
package com.example.dailyreport.master;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.ManagerGroupPermissionRepository;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MasterController {
    private final MasterDataRepository masterDataRepository;
    private final ManagerGroupPermissionRepository managerGroupPermissionRepository;

    public MasterController(MasterDataRepository masterDataRepository) {
        this(masterDataRepository, null);
    }

    @Autowired
    public MasterController(MasterDataRepository masterDataRepository,
                             ManagerGroupPermissionRepository managerGroupPermissionRepository) {
        this.masterDataRepository = masterDataRepository;
        this.managerGroupPermissionRepository = managerGroupPermissionRepository;
    }

    @GetMapping("/api/master/projects")
    /**
     * 有効な案件マスタを画面の選択肢として返す。
     */
    public List<MasterDataRepository.ProjectOption> projects() {
        return masterDataRepository.projects();
    }

    @GetMapping("/api/master/work-categories")
    /**
     * 有効な作業分類マスタを画面の選択肢として返す。
     */
    public List<MasterDataRepository.WorkCategoryOption> workCategories() {
        return masterDataRepository.workCategories();
    }

    @GetMapping("/api/master/holiday-types")
    /**
     * 有効な休日区分マスタと、各区分の入力ルールを返す。
     */
    public List<MasterDataRepository.HolidayTypeOption> holidayTypes() {
        return masterDataRepository.holidayTypes();
    }

    @GetMapping("/api/master/groups")
    /**
     * ロールに応じて、管理者は全グループ、上長は権限付与済みグループだけを返す。
     */
    public List<MasterDataRepository.GroupOption> groups(
            @AuthenticationPrincipal AuthenticatedUser authenticatedUser) {
        if (authenticatedUser == null || authenticatedUser.user().getRole() == com.example.dailyreport.auth.Role.EMPLOYEE) {
            return List.of();
        }
        List<MasterDataRepository.GroupOption> groups = masterDataRepository.groups();
        if (authenticatedUser.user().getRole() == com.example.dailyreport.auth.Role.ADMIN) {
            return groups;
        }
        // Why not: 上長権限Repositoryが利用できない場合に全グループを返すと、権限不備が情報漏えいへ直結するため空結果で fail-closed とする。
        if (managerGroupPermissionRepository == null) {
            return List.of();
        }
        List<String> permittedGroupIds = managerGroupPermissionRepository
                .permittedGroupIds(authenticatedUser.user().getUserId());
        return groups.stream()
                .filter(group -> permittedGroupIds.contains(group.groupId()))
                .toList();
    }
}
