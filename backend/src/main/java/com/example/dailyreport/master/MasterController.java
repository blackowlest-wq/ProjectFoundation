/**
 * 日報画面のプルダウンに使うマスタAPIを提供するController。
 * 案件、作業分類、休日区分をログイン済みユーザーへ返す。
 */
package com.example.dailyreport.master;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MasterController {
    private final MasterDataRepository masterDataRepository;

    public MasterController(MasterDataRepository masterDataRepository) {
        this.masterDataRepository = masterDataRepository;
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
}
