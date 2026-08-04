package com.example.dailyreport.master;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.Role;
import java.util.List;
import org.junit.jupiter.api.Test;

class MasterControllerUnitTest {
    @Test
    void managerWithoutPermissionRepositoryReceivesNoGroups() {
        MasterDataRepository masterDataRepository = mock(MasterDataRepository.class);
        when(masterDataRepository.groups()).thenReturn(List.of(
                new MasterDataRepository.GroupOption("G001", "第1開発グループ")));
        AppUser manager = new AppUser(
                "U-MANAGER", "E-MANAGER", "manager", "hash", "上長", Role.MANAGER,
                "G001", "第1開発グループ", "BT001", "標準休憩", "WT001", "通常勤務");

        List<MasterDataRepository.GroupOption> groups = new MasterController(masterDataRepository, null)
                .groups(new AuthenticatedUser(manager));

        assertThat(groups).isEmpty();
    }
}
